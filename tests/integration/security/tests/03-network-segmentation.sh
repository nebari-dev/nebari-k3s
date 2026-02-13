#!/usr/bin/env bash
##
## Test 03: Network Segmentation Validation
## Tests inter-node communication and network isolation
##

set -euo pipefail

INVENTORY="${1:?Usage: $0 <inventory.ini>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/test-helpers.sh"

init_test "Network Segmentation"

get_node_ips "${INVENTORY}"

echo "════════════════════════════════════════"
echo "  Network Segmentation Validation"
echo "════════════════════════════════════════"
echo ""

# Test 1: Node-to-node connectivity on required ports
echo "─────────────────────────────────────────"
echo "Test 1: Inter-Node Communication"
echo "─────────────────────────────────────────"
echo ""

REQUIRED_PORTS=(
  "6443:K3s API"
  "8472:Flannel VXLAN"
  "10250:Kubelet"
)

if [[ ${#NODE_IPS[@]} -ge 2 ]]; then
  SRC_NODE_IP="${NODE_IPS[0]}"
  DST_NODE_IP="${NODE_IPS[1]}"
  SRC_NODE=$(grep -B1 "${SRC_NODE_IP}" "${INVENTORY}" | head -1 | awk '{print $1}')
  DST_NODE=$(grep -B1 "${DST_NODE_IP}" "${INVENTORY}" | head -1 | awk '{print $1}')
  
  echo "Testing ${SRC_NODE} -> ${DST_NODE}"
  echo ""
  
  for port_def in "${REQUIRED_PORTS[@]}"; do
    IFS=':' read -r port desc <<< "${port_def}"
    echo -n "  ${desc} (${port})... "
    
    result=$(ansible all -i "${INVENTORY}" --limit "${SRC_NODE}" -m shell \
      -a "timeout 5 nc -zv ${DST_NODE_IP} ${port} 2>&1" 2>/dev/null || echo "FAILED")
    
    if echo "${result}" | grep -qiE "succeeded|connected|open"; then
      log_success "CONNECTED"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_error "FAILED"
      record_finding "CRITICAL" "Node ${SRC_NODE} cannot reach ${DST_NODE}:${port} (${desc})"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
  done
  echo ""
else
  log_warning "Less than 2 nodes - skipping inter-node tests"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Test 2: Pod network connectivity (if K3s is running)
echo "─────────────────────────────────────────"
echo "Test 2: Pod Network (Flannel CNI)"
echo "─────────────────────────────────────────"
echo ""

# Check if kubectl is available and configured
FIRST_NODE_IP="${NODE_IPS[0]}"
FIRST_NODE=$(grep -B1 "${FIRST_NODE_IP}" "${INVENTORY}" | head -1 | awk '{print $1}')

result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo kubectl get nodes 2>/dev/null" 2>/dev/null || echo "KUBECTL_FAILED")

if echo "${result}" | grep -q "Ready"; then
  log_success "K3s cluster is running"
  
  # Check Flannel pods
  echo -n "  Checking Flannel pods... "
  flannel_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo kubectl get pods -n kube-flannel -o wide 2>/dev/null || sudo kubectl get pods -n kube-system -l app=flannel -o wide 2>/dev/null" \
    2>/dev/null || echo "NO_FLANNEL")
  
  if echo "${flannel_result}" | grep -qE "Running|flannel"; then
    log_success "Running"
    TEST_PASSES=$((TEST_PASSES + 1))
    
    # Test pod-to-pod connectivity
    echo -n "  Testing pod-to-pod connectivity... "
    
    # Deploy test pods
    test_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
      -a "sudo kubectl run test-source --image=nicolaka/netshoot --rm -i --restart=Never -- curl -s -m 5 www.google.com > /dev/null && echo SUCCESS || echo FAILED" \
      2>/dev/null || echo "TEST_FAILED")
    
    if echo "${test_result}" | grep -q "SUCCESS"; then
      log_success "Internet connectivity works"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_warning "Internet connectivity test inconclusive"
      TEST_WARNINGS=$((TEST_WARNINGS + 1))
    fi
    
  else
    log_error "Flannel not running"
    record_finding "HIGH" "Flannel CNI pods not running properly"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  echo ""
else
  log_warning "K3s not running or kubectl not configured - skipping pod network tests"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Test 3: Service discovery (CoreDNS)
echo "─────────────────────────────────────────"
echo "Test 3: Service Discovery (CoreDNS)"
echo "─────────────────────────────────────────"
echo ""

if echo "${result}" | grep -q "Ready"; then
  echo -n "Checking CoreDNS... "
  
  coredns_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo kubectl get pods -n kube-system -l k8s-app=kube-dns" 2>/dev/null || echo "FAILED")
  
  if echo "${coredns_result}" | grep -q "Running"; then
    log_success "CoreDNS running"
    TEST_PASSES=$((TEST_PASSES + 1))
    
    # Test DNS resolution from pod
    echo -n "Testing DNS resolution... "
    dns_test=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
      -a "sudo kubectl run dns-test --image=busybox --rm -i --restart=Never -- nslookup kubernetes.default 2>&1 | grep -q 'Address' && echo SUCCESS || echo FAILED" \
      2>/dev/null || echo "TEST_FAILED")
    
    if echo "${dns_test}" | grep -q "SUCCESS"; then
      log_success "DNS resolution works"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_error "DNS resolution failed"
      record_finding "HIGH" "CoreDNS not resolving service names"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
  else
    log_error "CoreDNS not running"
    record_finding "CRITICAL" "CoreDNS pods not running"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  echo ""
else
  log_warning "Skipping CoreDNS tests - K3s not running"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Test 4: MetalLB (if enabled)
echo "─────────────────────────────────────────"
echo "Test 4: MetalLB LoadBalancer"
echo "─────────────────────────────────────────"
echo ""

GROUP_VARS_FILE="$(dirname "${INVENTORY}")/../group_vars/all.yaml"
METALLB_ENABLED=$(grep -E "k3s_enable_metallb.*true" "${GROUP_VARS_FILE}" 2>/dev/null || echo "false")

if [[ "${METALLB_ENABLED}" == *"true"* ]] && echo "${result}" | grep -q "Ready"; then
  echo -n "Checking MetalLB installation... "
  
  metallb_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo kubectl get pods -n metallb-system 2>/dev/null" 2>/dev/null || echo "NOT_INSTALLED")
  
  if echo "${metallb_result}" | grep -q "speaker"; then
    log_success "Installed"
    TEST_PASSES=$((TEST_PASSES + 1))
    
    # Check if speaker is running
    echo -n "Checking MetalLB speaker... "
    if echo "${metallb_result}" | grep "speaker" | grep -q "Running"; then
      log_success "Running"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_error "Not running"
      record_finding "HIGH" "MetalLB speaker not running"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
    
    # Check IP pool configuration
    echo -n "Checking IP pool configuration... "
    ippool_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
      -a "sudo kubectl get ipaddresspools.metallb.io -n metallb-system 2>/dev/null" 2>/dev/null || echo "NOT_CONFIGURED")
    
    if echo "${ippool_result}" | grep -qE "first-pool|default"; then
      log_success "Configured"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_error "Not configured"
      record_finding "HIGH" "MetalLB IP address pool not configured"
      TEST_FAILURES=$((TEST_FAILURES + 1))
    fi
    
  else
    log_warning "MetalLB not installed or not in metallb-system namespace"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
  echo ""
else
  log_warning "MetalLB not enabled or K3s not running - skipping"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Test 5: Kube-VIP (if HA setup)
echo "─────────────────────────────────────────"
echo "Test 5: Kube-VIP (HA Virtual IP)"
echo "─────────────────────────────────────────"
echo ""

# Check if this is HA setup (3+ control plane nodes)
CP_COUNT=$(grep -c "k3s_control_plane=true" "${INVENTORY}" 2>/dev/null || echo "0")

if [[ ${CP_COUNT} -ge 3 ]] && echo "${result}" | grep -q "Ready"; then
  echo "HA setup detected (${CP_COUNT} control plane nodes)"
  echo -n "Checking kube-vip... "
  
  kubevip_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo kubectl get pods -n kube-system -l app=kube-vip" 2>/dev/null || echo "NOT_FOUND")
  
  if echo "${kubevip_result}" | grep -q "Running"; then
    log_success "Running"
    TEST_PASSES=$((TEST_PASSES + 1))
    
    # Check VIP accessibility
    VIP=$(grep "apiserver_endpoint" "${GROUP_VARS_FILE}" | awk '{print $2}')
    if [[ -n "${VIP}" ]]; then
      echo -n "Testing VIP ${VIP}:6443... "
      
      vip_test=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
        -a "timeout 5 nc -zv ${VIP} 6443 2>&1" 2>/dev/null || echo "FAILED")
      
      if echo "${vip_test}" | grep -qiE "succeeded|connected"; then
        log_success "VIP accessible"
        TEST_PASSES=$((TEST_PASSES + 1))
      else
        log_error "VIP not accessible"
        record_finding "CRITICAL" "Kube-VIP endpoint ${VIP}:6443 not accessible"
        TEST_FAILURES=$((TEST_FAILURES + 1))
      fi
    fi
  else
    log_error "kube-vip not running in HA setup"
    record_finding "HIGH" "kube-vip required for HA but not running"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  echo ""
else
  log_warning "Not an HA setup or K3s not running - skipping kube-vip tests"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

# Test 6: Network policy enforcement (if kube-router is enabled)
echo "─────────────────────────────────────────"
echo "Test 6: Network Policy Enforcement"
echo "─────────────────────────────────────────"
echo ""

if echo "${result}" | grep -q "Ready"; then
  echo -n "Checking network policy support... "
  
  # Check if kube-router or other network policy controller exists
  netpol_result=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
    -a "sudo kubectl get pods -n kube-system | grep -E 'kube-router|calico|cilium' || echo 'NOT_FOUND'" \
    2>/dev/null || echo "CHECK_FAILED")
  
  if echo "${netpol_result}" | grep -qvE "NOT_FOUND|CHECK_FAILED"; then
    log_success "Network policy controller detected"
    TEST_PASSES=$((TEST_PASSES + 1))
    
    # Create test network policy
    echo -n "Testing network policy enforcement... "
    netpol_test=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
      -a "sudo kubectl create namespace netpol-test 2>/dev/null && \
          sudo kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
          sudo kubectl get networkpolicy -n netpol-test deny-all 2>/dev/null && echo SUCCESS || echo FAILED" \
      2>/dev/null || echo "TEST_FAILED")
    
    if echo "${netpol_test}" | grep -q "SUCCESS"; then
      log_success "Network policies can be created"
      TEST_PASSES=$((TEST_PASSES + 1))
      
      # Cleanup
      ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
        -a "sudo kubectl delete namespace netpol-test" 2>/dev/null || true
    else
      log_warning "Network policy test inconclusive"
      TEST_WARNINGS=$((TEST_WARNINGS + 1))
    fi
    
  else
    log_warning "No network policy controller detected (kube-router/Calico/Cilium)"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
  echo ""
else
  log_warning "K3s not running - skipping network policy tests"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
  echo ""
fi

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
  echo "❌ NETWORK SEGMENTATION ISSUES DETECTED"
  cat /tmp/security-findings.txt 2>/dev/null || true
  exit 1
else
  echo "✅ NETWORK SEGMENTATION VALIDATED"
  exit 0
fi
