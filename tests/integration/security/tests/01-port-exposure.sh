#!/usr/bin/env bash
##
## Test 01: Port Exposure Audit
## Validates no sensitive ports are exposed externally
##

set -euo pipefail

INVENTORY="${1:?Usage: $0 <inventory.ini>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/test-helpers.sh"

init_test "Port Exposure Audit"

# Extract node IPs from inventory
get_node_ips "${INVENTORY}"

# Define ports to check
CRITICAL_PORTS=(
  "6443:API Server"
  "10250:Kubelet API"
  "2379:etcd client"
  "2380:etcd peer"
)

NODEPORT_RANGE="30000-32767"
ALLOWED_PORTS=("22:SSH" "80:HTTP" "443:HTTPS")

echo "════════════════════════════════════════"
echo "  Port Exposure Security Audit"
echo "════════════════════════════════════════"
echo ""
echo "Testing ${#NODE_IPS[@]} nodes:"
for ip in "${NODE_IPS[@]}"; do
  echo "  - ${ip}"
done
echo ""

# Check if nmap is available
if ! command -v nmap &> /dev/null; then
  log_error "nmap not installed. Install with: sudo dnf install -y nmap"
  exit 1
fi

# Test 1: Critical ports should be blocked externally
echo "─────────────────────────────────────────"
echo "Test 1: Critical Ports Must Be Blocked"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  echo "Scanning ${node_ip}..."
  
  for port_def in "${CRITICAL_PORTS[@]}"; do
    IFS=':' read -r port desc <<< "${port_def}"
    
    echo -n "  Testing ${desc} (${port})... "
    
    # Use nmap to check if port is filtered/closed
    result=$(nmap -Pn -p "${port}" --host-timeout 10s "${node_ip}" 2>/dev/null | grep "${port}/tcp" | awk '{print $2}')
    
    if [[ "${result}" == "open" ]]; then
      log_error "FAIL - ${desc} (${port}) is OPEN on ${node_ip}"
      record_finding "CRITICAL" "Port ${port} (${desc}) exposed on ${node_ip}"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    elif [[ "${result}" == "filtered" ]] || [[ "${result}" == "closed" ]]; then
      log_success "PASS - ${desc} blocked (${result})"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_warning "WARN - Unable to determine state: ${result}"
      TEST_WARNINGS=$((TEST_WARNINGS + 1))
    fi
  done
  echo ""
done

# Test 2: NodePort range should be blocked
echo "─────────────────────────────────────────"
echo "Test 2: NodePort Range Must Be Blocked"
echo "─────────────────────────────────────────"
echo ""

# Sample 5 random ports from NodePort range
SAMPLE_PORTS=(30100 30500 31000 31500 32000)

for node_ip in "${NODE_IPS[@]}"; do
  echo "Checking NodePort range on ${node_ip}..."
  
  open_nodeports=0
  for port in "${SAMPLE_PORTS[@]}"; do
    result=$(nmap -Pn -p "${port}" --host-timeout 5s "${node_ip}" 2>/dev/null | grep "${port}/tcp" | awk '{print $2}')
    
    if [[ "${result}" == "open" ]]; then
      log_error "  NodePort ${port} is OPEN"
      open_nodeports=$((open_nodeports + 1))
    fi
  done
  
  if [[ ${open_nodeports} -eq 0 ]]; then
    log_success "  PASS - NodePort range properly blocked"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "  FAIL - ${open_nodeports} NodePorts exposed"
    record_finding "HIGH" "NodePort range exposed on ${node_ip}"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  echo ""
done

# Test 3: SSH should be restricted (check from current IP)
echo "─────────────────────────────────────────"
echo "Test 3: SSH Access Control"
echo "─────────────────────────────────────────"
echo ""

MY_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
echo "Testing from IP: ${MY_IP}"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  echo -n "SSH to ${node_ip}... "
  
  # Try to connect with short timeout
  if timeout 5 nc -zv "${node_ip}" 22 &>/dev/null; then
    log_warning "ACCESSIBLE (verify IP ${MY_IP} is in k3s_admin_cidrs)"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  else
    log_success "BLOCKED (as expected if not in admin CIDR)"
    TEST_PASSES=$((TEST_PASSES + 1))
  fi
done
echo ""

# Test 4: Ingress ports (80/443) - conditional
echo "─────────────────────────────────────────"
echo "Test 4: Ingress Port Accessibility"
echo "─────────────────────────────────────────"
echo ""

# Check if k3s_expose_ingress_publicly is set
EXPOSE_INGRESS=$(grep -E "k3s_expose_ingress_publicly.*true" "$(dirname "${INVENTORY}")/../group_vars/all.yaml" 2>/dev/null || echo "false")

for node_ip in "${NODE_IPS[@]}"; do
  for port_def in "${ALLOWED_PORTS[@]}"; do
    IFS=':' read -r port desc <<< "${port_def}"
    
    if [[ "${port}" == "80" ]] || [[ "${port}" == "443" ]]; then
      echo -n "${desc} (${port}) on ${node_ip}... "
      
      result=$(nmap -Pn -p "${port}" --host-timeout 5s "${node_ip}" 2>/dev/null | grep "${port}/tcp" | awk '{print $2}')
      
      if [[ "${result}" == "open" ]]; then
        if [[ "${EXPOSE_INGRESS}" == *"true"* ]]; then
          log_success "OPEN (configured publicly)"
          TEST_PASSES=$((TEST_PASSES + 1))
        else
          log_warning "OPEN (k3s_expose_ingress_publicly may be false)"
          TEST_WARNINGS=$((TEST_WARNINGS + 1))
        fi
      else
        log_success "BLOCKED (${result})"
        TEST_PASSES=$((TEST_PASSES + 1))
      fi
    fi
  done
done
echo ""

# Test 5: Full comprehensive scan (detailed)
echo "─────────────────────────────────────────"
echo "Test 5: Comprehensive Port Scan"
echo "─────────────────────────────────────────"
echo ""

# Get first control plane IP for detailed scan
FIRST_NODE="${NODE_IPS[0]}"
echo "Running detailed scan on ${FIRST_NODE}..."
echo ""

# Scan common K8s ports
nmap -Pn -sV -p 22,80,443,6443,2379,2380,8472,10250,10251,10252,30000-30100 "${FIRST_NODE}" 2>/dev/null | tee /tmp/port-scan-${FIRST_NODE}.txt

echo ""
echo -n "Analyzing scan results... "

# Check for any unexpected open ports
UNEXPECTED_OPEN=$(grep "open" /tmp/port-scan-${FIRST_NODE}.txt | grep -v "22/tcp" | grep -v "filtered" || true)

if [[ -n "${UNEXPECTED_OPEN}" ]]; then
  log_error "FAIL - Unexpected open ports detected"
  echo "${UNEXPECTED_OPEN}"
  record_finding "HIGH" "Unexpected open ports on ${FIRST_NODE}: ${UNEXPECTED_OPEN}"
  TEST_FAILURES=$((TEST_FAILURES + 1))
else
  log_success "PASS - No unexpected open ports"
  TEST_PASSES=$((TEST_PASSES + 1))
fi

echo ""

# Test 6: Internal node-to-node connectivity (if we have SSH access)
echo "─────────────────────────────────────────"
echo "Test 6: Internal Node Connectivity"
echo "─────────────────────────────────────────"
echo ""

# This test requires SSH access to nodes
if ansible all -i "${INVENTORY}" -m ping &>/dev/null; then
  log_success "Ansible connectivity verified"
  
  # Check if nodes can reach each other on required ports
  echo "Testing node-to-node connectivity..."
  
  # Get first two nodes
  if [[ ${#NODE_IPS[@]} -ge 2 ]]; then
    SRC_NODE="${NODE_IPS[0]}"
    DST_NODE="${NODE_IPS[1]}"
    
    # Test K3s required ports between nodes
    for port in 6443 10250 8472; do
      echo -n "  ${SRC_NODE} -> ${DST_NODE}:${port}... "
      
      result=$(ansible all -i "${INVENTORY}" -m shell \
        -a "nc -zv ${DST_NODE} ${port}" \
        --limit "$(grep -B1 "${SRC_NODE}" "${INVENTORY}" | head -1)" \
        2>&1 || true)
      
      if echo "${result}" | grep -q "succeeded"; then
        log_success "CONNECTED"
        TEST_PASSES=$((TEST_PASSES + 1))
      else
        log_error "FAILED"
        record_finding "HIGH" "Node ${SRC_NODE} cannot reach ${DST_NODE}:${port}"
        TEST_FAILURES=$((TEST_FAILURES + 1))
      fi
    done
  fi
  echo ""
else
  log_warning "Ansible not configured - skipping internal connectivity tests"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Generate test summary
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
  echo "❌ CRITICAL FINDINGS DETECTED"
  echo ""
  echo "Security issues found:"
  cat /tmp/security-findings.txt 2>/dev/null || true
  echo ""
  exit 1
else
  echo "✅ ALL PORT EXPOSURE TESTS PASSED"
  exit 0
fi
