#!/usr/bin/env bash
##
## Test 02: Firewall Configuration Validation
## Validates firewalld zones and rules are correctly configured
##

set -euo pipefail

INVENTORY="${1:?Usage: $0 <inventory.ini>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/test-helpers.sh"

init_test "Firewall Configuration"

get_node_ips "${INVENTORY}"

echo "════════════════════════════════════════"
echo "  Firewall Configuration Validation"
echo "════════════════════════════════════════"
echo ""

# Test 1: Verify k3s-cluster zone exists
echo "─────────────────────────────────────────"
echo "Test 1: k3s-cluster Zone Configuration"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
  echo "Checking ${node_name} (${node_ip})..."
  
  # Check if k3s-cluster zone exists
  result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
    -a "sudo firewall-cmd --zone=k3s-cluster --list-all" 2>/dev/null || echo "FAILED")
  
  if echo "${result}" | grep -q "k3s-cluster"; then
    log_success "  ✓ k3s-cluster zone exists"
    TEST_PASSES=$((TEST_PASSES + 1))
    
    # Check target is DROP
    if echo "${result}" | grep -q "target: DROP"; then
      log_success "  ✓ Zone target is DROP (secure default)"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_error "  ✗ Zone target is not DROP"
      record_finding "HIGH" "${node_name}: k3s-cluster zone target not set to DROP"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
    
    # Check sources include node IPs
    sources_count=$(echo "${result}" | grep -c "sources:" || echo "0")
    if [[ ${sources_count} -gt 0 ]]; then
      log_success "  ✓ Zone has source restrictions"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_warning "  ⚠ No source restrictions found"
      TEST_WARNINGS=$((TEST_WARNINGS + 1))
    fi
    
  else
    log_error "  ✗ k3s-cluster zone not found"
    record_finding "CRITICAL" "${node_name}: k3s-cluster firewall zone missing"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  echo ""
done

# Test 2: Verify public zone blocks sensitive ports
echo "─────────────────────────────────────────"
echo "Test 2: Public Zone Port Blocking"
echo "─────────────────────────────────────────"
echo ""

BLOCKED_PORTS=(6443 10250 2379 2380)

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
  echo "Checking ${node_name}..."
  
  # Get public zone rich rules
  result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
    -a "sudo firewall-cmd --zone=public --list-rich-rules" 2>/dev/null || echo "FAILED")
  
  for port in "${BLOCKED_PORTS[@]}"; do
    echo -n "  Port ${port}... "
    
    if echo "${result}" | grep -q "port=\"${port}\".*reject"; then
      log_success "BLOCKED"
      TEST_PASSES=$((TEST_PASSES + 1))
    elif echo "${result}" | grep -q "port=\"${port}\".*drop"; then
      log_success "DROPPED"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_error "NOT BLOCKED"
      record_finding "CRITICAL" "${node_name}: Port ${port} not blocked in public zone"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
  done
  echo ""
done

# Test 3: Verify NodePort range is blocked
echo "─────────────────────────────────────────"
echo "Test 3: NodePort Range Blocking"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
  echo -n "Checking ${node_name}... "
  
  result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
    -a "sudo firewall-cmd --zone=public --list-rich-rules" 2>/dev/null || echo "FAILED")
  
  if echo "${result}" | grep -q "port=\"30000-32767\""; then
    log_success "NodePort range blocked"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "NodePort range NOT blocked"
    record_finding "HIGH" "${node_name}: NodePort range 30000-32767 not blocked"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
done
echo ""

# Test 4: Verify admin CIDR restrictions
echo "─────────────────────────────────────────"
echo "Test 4: Admin CIDR Access Control"
echo "─────────────────────────────────────────"
echo ""

# Read k3s_admin_cidrs from group_vars
GROUP_VARS_FILE="$(dirname "${INVENTORY}")/../group_vars/all.yaml"
if [[ -f "${GROUP_VARS_FILE}" ]]; then
  ADMIN_CIDRS=$(grep -A5 "k3s_admin_cidrs:" "${GROUP_VARS_FILE}" | grep -E "^\s+-\s+" | sed 's/^.*- //' || echo "")
  
  if [[ -n "${ADMIN_CIDRS}" ]]; then
    echo "Configured admin CIDRs:"
    echo "${ADMIN_CIDRS}" | while read -r cidr; do
      echo "  - ${cidr}"
    done
    echo ""
    
    for node_ip in "${NODE_IPS[@]}"; do
      node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
      echo "Checking ${node_name}..."
      
      result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
        -a "sudo firewall-cmd --zone=public --list-rich-rules" 2>/dev/null || echo "FAILED")
      
      # Check if SSH is restricted
      if echo "${result}" | grep -q "service name=\"ssh\""; then
        log_success "  ✓ SSH has source restrictions"
        TEST_PASSES=$((TEST_PASSES + 1))
      else
        log_warning "  ⚠ SSH may not have source restrictions"
        TEST_WARNINGS=$((TEST_WARNINGS + 1))
      fi
      
      # Check if API (6443) has source restrictions
      if echo "${result}" | grep -q "port=\"6443\".*source"; then
        log_success "  ✓ API server has admin CIDR restrictions"
        TEST_PASSES=$((TEST_PASSES + 1))
      else
        log_warning "  ⚠ API server may not have CIDR restrictions"
        TEST_WARNINGS=$((TEST_WARNINGS + 1))
      fi
    done
    echo ""
  else
    log_warning "No k3s_admin_cidrs configured (using empty list)"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
    echo ""
  fi
else
  log_error "group_vars/all.yaml not found"
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo ""
fi

# Test 5: Verify firewall persistence
echo "─────────────────────────────────────────"
echo "Test 5: Configuration Persistence"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
  echo -n "Checking ${node_name}... "
  
  # Check if runtime matches permanent configuration
  result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
    -a "sudo firewall-cmd --list-all-zones | diff - <(sudo firewall-cmd --permanent --list-all-zones) || true" \
    2>/dev/null || echo "FAILED")
  
  if [[ -z "${result}" ]] || [[ "${result}" == *"SUCCESS"* ]]; then
    log_success "Runtime matches permanent config"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_warning "Runtime and permanent configs differ"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
done
echo ""

# Test 6: Verify firewalld is active
echo "─────────────────────────────────────────"
echo "Test 6: Firewalld Service Status"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
  echo -n "Checking ${node_name}... "
  
  result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
    -a "sudo systemctl is-active firewalld" 2>/dev/null || echo "FAILED")
  
  if echo "${result}" | grep -q "active"; then
    log_success "Active and running"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "NOT active"
    record_finding "CRITICAL" "${node_name}: firewalld service not active"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
done
echo ""

# Test 7: Verify zone priority order
echo "─────────────────────────────────────────"
echo "Test 7: Zone Priority Validation"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(grep -B1 "${node_ip}" "${INVENTORY}" | head -1 | awk '{print $1}')
  echo "Checking ${node_name}..."
  
  # Get active zones
  result=$(ansible all -i "${INVENTORY}" --limit "${node_name}" -m shell \
    -a "sudo firewall-cmd --get-active-zones" 2>/dev/null || echo "FAILED")
  
  if echo "${result}" | grep -q "k3s-cluster"; then
    log_success "  ✓ k3s-cluster zone is active"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "  ✗ k3s-cluster zone not active"
    record_finding "HIGH" "${node_name}: k3s-cluster zone not in active zones"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  
  if echo "${result}" | grep -q "public"; then
    log_success "  ✓ public zone is active"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_warning "  ⚠ public zone not active"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
  echo ""
done

# Generate summary
echo "════════════════════════════════════════"
echo "  Test Summary"
echo "════════════════════════════════════════"
echo ""
echo "Total Tests:    $((TEST_PASSES + TEST_FAILURES + TEST_WARNINGS))"
echo "Passed:         ${TEST_PASSES}"
echo "Failed:         ${TEST_FAILURES}"
echo "Warnings:       ${TEST_WARNINGS}"
echo ""

if [[ ${TEST_FAILURES} -gt 0 ]]; then
  echo "❌ FIREWALL CONFIGURATION ISSUES DETECTED"
  cat /tmp/security-findings.txt 2>/dev/null || true
  exit 1
else
  echo "✅ FIREWALL CONFIGURATION VALIDATED"
  exit 0
fi
