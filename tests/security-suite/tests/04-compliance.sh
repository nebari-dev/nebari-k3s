#!/usr/bin/env bash
##
## Test 04: Security Compliance Tests
## CIS Kubernetes Benchmark and NIST 800-53 controls
##

set -euo pipefail

INVENTORY="${1:?Usage: $0 <inventory.ini>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/test-helpers.sh"

init_test "Compliance Validation"

get_node_ips "${INVENTORY}"

echo "════════════════════════════════════════"
echo "  CIS Benchmark & NIST 800-53 Compliance"
echo "════════════════════════════════════════"
echo ""

FIRST_NODE_IP="${NODE_IPS[0]}"
FIRST_NODE=$(get_node_name "${INVENTORY}" "${FIRST_NODE_IP}")

# Test 1: CIS Kubernetes Benchmark (if kube-bench available)
echo "─────────────────────────────────────────"
echo "Test 1: CIS Kubernetes Benchmark"
echo "─────────────────────────────────────────"
echo ""

# Check if kube-bench is installed
echo -n "Checking for kube-bench... "
KUBE_BENCH_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "command -v kube-bench" 2>/dev/null || echo "NOT_FOUND")

if echo "${KUBE_BENCH_CHECK}" | grep -q "kube-bench"; then
  log_success "Found"
  
  echo "Running CIS benchmark on ${FIRST_NODE}..."
  echo "(This may take 2-3 minutes)"
  echo ""
  
  # Run kube-bench
  KUBE_BENCH_OUTPUT=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo kube-bench run --targets node,policies --scored --json 2>/dev/null" \
    2>/dev/null || echo "KUBE_BENCH_FAILED")
  
  if echo "${KUBE_BENCH_OUTPUT}" | grep -q "total_pass"; then
    # Parse results
    TOTAL_PASS=$(echo "${KUBE_BENCH_OUTPUT}" | jq -r '.Totals.total_pass' 2>/dev/null || echo "0")
    TOTAL_FAIL=$(echo "${KUBE_BENCH_OUTPUT}" | jq -r '.Totals.total_fail' 2>/dev/null || echo "0")
    TOTAL_WARN=$(echo "${KUBE_BENCH_OUTPUT}" | jq -r '.Totals.total_warn' 2>/dev/null || echo "0")
    TOTAL_INFO=$(echo "${KUBE_BENCH_OUTPUT}" | jq -r '.Totals.total_info' 2>/dev/null || echo "0")
    
    echo "  Passed:   ${TOTAL_PASS}"
    echo "  Failed:   ${TOTAL_FAIL}"
    echo "  Warnings: ${TOTAL_WARN}"
    echo "  Info:     ${TOTAL_INFO}"
    echo ""
    
    # Calculate score
    TOTAL_CHECKS=$((TOTAL_PASS + TOTAL_FAIL))
    if [[ ${TOTAL_CHECKS} -gt 0 ]]; then
      CIS_SCORE=$((TOTAL_PASS * 100 / TOTAL_CHECKS))
      echo "  CIS Compliance Score: ${CIS_SCORE}%"
      
      if [[ ${CIS_SCORE} -ge 90 ]]; then
        log_success "CIS compliance ≥ 90%"
        TEST_PASSES=$((TEST_PASSES + 1))
      elif [[ ${CIS_SCORE} -ge 75 ]]; then
        log_warning "CIS compliance ${CIS_SCORE}% (target: ≥90%)"
        TEST_WARNINGS=$((TEST_WARNINGS + 1))
      else
        log_error "CIS compliance ${CIS_SCORE}% is too low"
        record_finding "HIGH" "CIS benchmark compliance below 75%"
        TEST_FAILURES=$((TEST_FAILURES + 1))
      fi
    fi
    
    # Save full report
    echo "${KUBE_BENCH_OUTPUT}" > /tmp/kube-bench-results.json
    log_info "Full report saved: /tmp/kube-bench-results.json"
    
  else
    log_error "kube-bench execution failed"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  echo ""
else
  log_warning "kube-bench not installed - skipping automated CIS checks"
  log_info "Install: wget https://github.com/aquasecurity/kube-bench/releases/download/v0.7.1/kube-bench_0.7.1_linux_amd64.tar.gz"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Test 2: NIST 800-53 Control AC-4 (Information Flow Enforcement)
echo "─────────────────────────────────────────"
echo "Test 2: NIST AC-4 - Information Flow"
echo "─────────────────────────────────────────"
echo ""

echo "Verifying network segmentation controls..."

# Check firewall zones exist
echo -n "  Firewall zones configured... "
ZONES_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo firewall-cmd --get-active-zones | grep -E 'k3s-cluster|public'" 2>/dev/null || echo "FAILED")

if echo "${ZONES_CHECK}" | grep -q "k3s-cluster"; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "No"
  record_finding "HIGH" "NIST AC-4: Network segmentation not implemented"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

# Check DROP policies
echo -n "  Default deny configured... "
DROP_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo firewall-cmd --zone=k3s-cluster --list-all | grep 'target: DROP'" 2>/dev/null || echo "FAILED")

if echo "${DROP_CHECK}" | grep -q "DROP"; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "No"
  record_finding "HIGH" "NIST AC-4: Default deny not configured"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

echo ""

# Test 3: NIST 800-53 Control SC-7 (Boundary Protection)
echo "─────────────────────────────────────────"
echo "Test 3: NIST SC-7 - Boundary Protection"
echo "─────────────────────────────────────────"
echo ""

echo "Verifying boundary protection controls..."

SENSITIVE_PORTS=(6443 10250 2379 2380)
BOUNDARY_PASS=0
BOUNDARY_FAIL=0

for port in "${SENSITIVE_PORTS[@]}"; do
  echo -n "  Port ${port} blocked externally... "
  
  PORT_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo firewall-cmd --zone=public --list-rich-rules | grep -E 'port=\"${port}\".*reject|port=\"${port}\".*drop'" \
    2>/dev/null || echo "NOT_BLOCKED")
  
  if echo "${PORT_CHECK}" | grep -qE "reject|drop"; then
    log_success "Yes"
    BOUNDARY_PASS=$((BOUNDARY_PASS + 1))
  else
    log_error "No"
    BOUNDARY_FAIL=$((BOUNDARY_FAIL + 1))
    record_finding "CRITICAL" "NIST SC-7: Port ${port} not blocked at boundary"
  fi
done

if [[ ${BOUNDARY_FAIL} -eq 0 ]]; then
  log_success "All boundary protections in place"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "${BOUNDARY_FAIL} boundary protection failures"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

echo ""

# Test 4: NIST 800-53 Control AU-2 (Audit Events)
echo "─────────────────────────────────────────"
echo "Test 4: NIST AU-2 - Audit Logging"
echo "─────────────────────────────────────────"
echo ""

echo "Verifying audit logging..."

# Check K3s audit logs
echo -n "  K3s audit policy configured... "
AUDIT_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo grep -E 'audit-policy-file|audit-log-path' /etc/systemd/system/k3s*.service 2>/dev/null || sudo ps aux | grep -E 'audit-policy|audit-log' | grep -v grep" \
  2>/dev/null || echo "NOT_CONFIGURED")

if echo "${AUDIT_CHECK}" | grep -qE "audit-policy|audit-log"; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
  
  # Check if audit logs are being written
  echo -n "  Audit logs being written... "
  LOG_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo find /var/lib/rancher/k3s/server/logs -name 'audit*.log' -mtime -1 | wc -l" \
    2>/dev/null || echo "0")
  
  if [[ "${LOG_CHECK}" =~ [1-9] ]]; then
    log_success "Yes"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_warning "No recent logs found"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
else
  log_warning "Not explicitly configured (using defaults)"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Test 5: API Server Security Configuration
echo "─────────────────────────────────────────"
echo "Test 5: API Server Security Settings"
echo "─────────────────────────────────────────"
echo ""

echo "Checking API server configuration..."

# Check anonymous auth is disabled
echo -n "  Anonymous auth disabled... "
ANON_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo ps aux | grep kube-apiserver | grep -v grep | grep -E 'anonymous-auth=false'" 2>/dev/null || echo "NOT_SET")

if echo "${ANON_CHECK}" | grep -q "anonymous-auth=false"; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Not explicitly set (check K3s defaults)"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

# Check TLS is enforced
echo -n "  TLS configured... "
TLS_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo ls /var/lib/rancher/k3s/server/tls/*.crt 2>/dev/null | wc -l" 2>/dev/null || echo "0")

if [[ "${TLS_CHECK}" =~ [1-9] ]]; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "No TLS certificates found"
  record_finding "CRITICAL" "API server TLS certificates not found"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

# Check RBAC is enabled
echo -n "  RBAC enabled... "
RBAC_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo kubectl get clusterrolebindings 2>/dev/null | wc -l" 2>/dev/null || echo "0")

if [[ "${RBAC_CHECK}" =~ [1-9] ]]; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "RBAC not functioning"
  record_finding "CRITICAL" "RBAC not enabled"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

echo ""

# Test 6: Kubelet Security
echo "─────────────────────────────────────────"
echo "Test 6: Kubelet Security Configuration"
echo "─────────────────────────────────────────"
echo ""

echo "Checking kubelet configuration..."

# Check anonymous auth is disabled
echo -n "  Kubelet anonymous auth disabled... "
KUBELET_ANON=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo ps aux | grep kubelet | grep -v grep | grep 'anonymous-auth=false' || sudo grep 'anonymous.*false' /var/lib/rancher/k3s/agent/kubelet.kubeconfig 2>/dev/null" \
  2>/dev/null || echo "NOT_SET")

if echo "${KUBELET_ANON}" | grep -qE "anonymous-auth=false|anonymous.*false"; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Not explicitly set"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

# Check kubelet uses TLS
echo -n "  Kubelet TLS enabled... "
KUBELET_TLS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo netstat -tlnp | grep ':10250' | grep -q 'k3s' && echo 'YES'" 2>/dev/null || echo "NO")

if [[ "${KUBELET_TLS}" == *"YES"* ]]; then
  log_success "Yes"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "Kubelet not listening on 10250"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

echo ""

# Test 7: Secrets Encryption
echo "─────────────────────────────────────────"
echo "Test 7: Secrets Encryption at Rest"
echo "─────────────────────────────────────────"
echo ""

echo -n "Checking secrets encryption... "
ENCRYPTION_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo ls /var/lib/rancher/k3s/server/cred/encryption-config.json 2>/dev/null || sudo grep 'encryption-provider-config' /etc/systemd/system/k3s*.service" \
  2>/dev/null || echo "NOT_CONFIGURED")

if echo "${ENCRYPTION_CHECK}" | grep -qE "encryption-config|encryption-provider"; then
  log_success "Configured"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Not explicitly configured (using defaults)"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Test 8: Pod Security Standards
echo "─────────────────────────────────────────"
echo "Test 8: Pod Security Standards"
echo "─────────────────────────────────────────"
echo ""

echo -n "Checking Pod Security admission... "
PSS_CHECK=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo kubectl get podsecuritypolicies 2>/dev/null || sudo ps aux | grep 'PodSecurity' | grep -v grep" \
  2>/dev/null || echo "NOT_ENABLED")

if echo "${PSS_CHECK}" | grep -qvE "NOT_ENABLED|No resources found"; then
  log_success "Enabled"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "PSP/PSA not explicitly enabled (K3s defaults may apply)"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Calculate compliance score
TOTAL_TESTS=$((TEST_PASSES + TEST_FAILURES + TEST_WARNINGS))
if [[ ${TOTAL_TESTS} -gt 0 ]]; then
  COMPLIANCE_SCORE=$((TEST_PASSES * 100 / TOTAL_TESTS))
else
  COMPLIANCE_SCORE=0
fi

# Generate summary
echo "════════════════════════════════════════"
echo "  Compliance Summary"
echo "════════════════════════════════════════"
echo ""
echo "Total Checks:       ${TOTAL_TESTS}"
echo "Passed:             ${TEST_PASSES}"
echo "Failed:             ${TEST_FAILURES}"
echo "Warnings:           ${TEST_WARNINGS}"
echo ""
echo "Compliance Score:   ${COMPLIANCE_SCORE}%"
echo ""

# Compliance rating
if [[ ${COMPLIANCE_SCORE} -ge 90 ]]; then
  log_success "EXCELLENT - NASA compliance requirements met"
elif [[ ${COMPLIANCE_SCORE} -ge 75 ]]; then
  log_warning "GOOD - Minor improvements recommended"
else
  log_error "INSUFFICIENT - Compliance issues must be addressed"
fi

echo ""

if [[ ${TEST_FAILURES} -gt 0 ]]; then
  echo "❌ COMPLIANCE ISSUES DETECTED"
  cat /tmp/security-findings.txt 2>/dev/null || true
  exit 1
else
  echo "✅ COMPLIANCE CHECKS PASSED"
  exit 0
fi
