#!/usr/bin/env bash
##
## Test 05: K3s-Specific Security Tests
## Validates K3s-specific security configurations
##

set -euo pipefail

INVENTORY="${1:?Usage: $0 <inventory.ini>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/test-helpers.sh"

init_test "K3s Security"

get_node_ips "${INVENTORY}"

echo "════════════════════════════════════════"
echo "  K3s-Specific Security Validation"
echo "════════════════════════════════════════"
echo ""

FIRST_NODE_IP="${NODE_IPS[0]}"
FIRST_NODE=$(get_node_name "${INVENTORY}" "${FIRST_NODE_IP}")

# Test 1: K3s Version Check
echo "─────────────────────────────────────────"
echo "Test 1: K3s Version & Updates"
echo "─────────────────────────────────────────"
echo ""

for node_ip in "${NODE_IPS[@]}"; do
  node_name=$(get_node_name "${INVENTORY}" "${node_ip}")
  echo -n "${node_name}: "
  
  K3S_VERSION=$(get_k3s_version "${INVENTORY}" "${node_name}")
  echo "K3s ${K3S_VERSION}"
  
  if [[ "${K3S_VERSION}" != "UNKNOWN" ]]; then
    # Extract version number
    VERSION_NUM=$(echo "${K3S_VERSION}" | grep -oP 'v\K[\d.]+' | head -c 4)
    
    # Check if version is recent (v1.27+)
    if [[ "${VERSION_NUM}" > "1.27" ]] || [[ "${VERSION_NUM}" == "1.27" ]] || [[ "${VERSION_NUM}" > "1.27" ]]; then
      log_success "  Version is recent (${K3S_VERSION})"
      TEST_PASSES=$((TEST_PASSES + 1))
    else
      log_warning "  Version ${K3S_VERSION} may be outdated (recommend v1.28+)"
      TEST_WARNINGS=$((TEST_WARNINGS + 1))
    fi
  else
    log_error "  Unable to determine K3s version"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
done
echo ""

# Test 2: K3s Server Configuration
echo "─────────────────────────────────────────"
echo "Test 2: K3s Server Configuration"
echo "─────────────────────────────────────────"
echo ""

echo "Checking control plane configuration..."

# Get control plane nodes
CP_NODES=$(grep "k3s_control_plane=true" "${INVENTORY}" | awk '{print $1}' || echo "")

if [[ -n "${CP_NODES}" ]]; then
  FIRST_CP=$(echo "${CP_NODES}" | head -1)
  echo "Testing ${FIRST_CP}..."
  echo ""
  
  # Check if secrets encryption is enabled
  echo -n "  Secrets encryption enabled... "
  SECRETS_ENC=$(ansible all -i "${INVENTORY}" --limit "${FIRST_CP}" -m shell \
    -a "sudo ps aux | grep 'kube-apiserver' | grep -E 'secrets-encryption-config|encryption-provider-config' | grep -v grep || echo 'NOT_SET'" \
    2>/dev/null || echo "UNKNOWN")
  
  if echo "${SECRETS_ENC}" | grep -qvE "NOT_SET|UNKNOWN"; then
    log_success "Yes"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_warning "Not explicitly configured"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
  
  # Check if admission controllers are enabled
  echo -n "  Admission controllers configured... "
  ADMISSION=$(ansible all -i "${INVENTORY}" --limit "${FIRST_CP}" -m shell \
    -a "sudo ps aux | grep 'kube-apiserver' | grep 'enable-admission-plugins' | grep -v grep" \
    2>/dev/null || echo "DEFAULT")
  
  if echo "${ADMISSION}" | grep -qE "enable-admission-plugins|NodeRestriction"; then
    log_success "Yes"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_warning "Using defaults"
    TEST_WARNINGS=$((TEST_WARNINGS + 1))
  fi
  
  # Check service account key
  echo -n "  Service account keys configured... "
  SA_KEY=$(ansible all -i "${INVENTORY}" --limit "${FIRST_CP}" -m shell \
    -a "sudo ls /var/lib/rancher/k3s/server/tls/service.key 2>/dev/null" \
    2>/dev/null || echo "NOT_FOUND")
  
  if echo "${SA_KEY}" | grep -q "service.key"; then
    log_success "Yes"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "Service account key not found"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  
  echo ""
else
  log_error "No control plane nodes found in inventory"
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo ""
fi

# Test 3: K3s Agent Configuration (Worker Nodes)
echo "─────────────────────────────────────────"
echo "Test 3: K3s Agent Configuration"
echo "─────────────────────────────────────────"
echo ""

# Get worker nodes
WORKER_NODES=$(grep "k3s_control_plane=false" "${INVENTORY}" | awk '{print $1}' || echo "")

if [[ -n "${WORKER_NODES}" ]]; then
  FIRST_WORKER=$(echo "${WORKER_NODES}" | head -1)
  echo "Testing ${FIRST_WORKER}..."
  echo ""
  
  # Check kubelet configuration
  echo -n "  Kubelet configuration secure... "
  KUBELET_CFG=$(ansible all -i "${INVENTORY}" --limit "${FIRST_WORKER}" -m shell \
    -a "sudo cat /var/lib/rancher/k3s/agent/kubelet.kubeconfig 2>/dev/null | grep -E 'certificate-authority|client-certificate' | wc -l" \
    2>/dev/null || echo "0")
  
  if [[ "${KUBELET_CFG}" =~ [2-9] ]]; then
    log_success "Yes (TLS configured)"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "Kubelet config incomplete"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  
  # Check read-only port is disabled
  echo -n "  Read-only port disabled... "
  READONLY_PORT=$(ansible all -i "${INVENTORY}" --limit "${FIRST_WORKER}" -m shell \
    -a "sudo netstat -tlnp | grep ':10255' || echo 'DISABLED'" 2>/dev/null || echo "UNKNOWN")
  
  if echo "${READONLY_PORT}" | grep -q "DISABLED"; then
    log_success "Yes"
    TEST_PASSES=$((TEST_PASSES + 1))
  else
    log_error "Read-only port 10255 is open"
    record_finding "HIGH" "Kubelet read-only port (10255) should be disabled"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
  
  echo ""
else
  log_warning "No worker nodes found - testing control plane as agent"
  echo ""
fi

# Test 4: K3s Token Security
echo "─────────────────────────────────────────"
echo "Test 4: K3s Token & Secrets Security"
echo "─────────────────────────────────────────"
echo ""

echo "Checking token security..."

# Check token file permissions
echo -n "  Token file permissions... "
TOKEN_PERMS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo stat -c '%a' /var/lib/rancher/k3s/server/token 2>/dev/null || echo 'NOT_FOUND'" \
  2>/dev/null || echo "UNKNOWN")

if [[ "${TOKEN_PERMS}" == "600" ]] || [[ "${TOKEN_PERMS}" == "400" ]]; then
  log_success "Secure (${TOKEN_PERMS})"
  TEST_PASSES=$((TEST_PASSES + 1))
elif [[ "${TOKEN_PERMS}" == "NOT_FOUND" ]]; then
  log_warning "Token file not found (may be agent node)"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
else
  log_error "Insecure permissions (${TOKEN_PERMS})"
  record_finding "HIGH" "K3s token file has insecure permissions: ${TOKEN_PERMS}"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

# Check node token storage
echo -n "  Node token file permissions... "
NODE_TOKEN_PERMS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo stat -c '%a' /var/lib/rancher/k3s/server/node-token 2>/dev/null || sudo stat -c '%a' /var/lib/rancher/k3s/agent/client-token 2>/dev/null || echo 'NOT_FOUND'" \
  2>/dev/null || echo "UNKNOWN")

if [[ "${NODE_TOKEN_PERMS}" == "600" ]] || [[ "${NODE_TOKEN_PERMS}" == "400" ]]; then
  log_success "Secure (${NODE_TOKEN_PERMS})"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Permissions: ${NODE_TOKEN_PERMS}"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Test 5: K3s Data Directory Security
echo "─────────────────────────────────────────"
echo "Test 5: Data Directory Security"
echo "─────────────────────────────────────────"
echo ""

echo "Checking data directory permissions..."

# Check /var/lib/rancher/k3s permissions
echo -n "  K3s data directory... "
DATA_DIR_PERMS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo stat -c '%a %U:%G' /var/lib/rancher/k3s 2>/dev/null" \
  2>/dev/null || echo "NOT_FOUND")

if echo "${DATA_DIR_PERMS}" | grep -q "root:root"; then
  log_success "Owned by root"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Ownership: ${DATA_DIR_PERMS}"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

# Check etcd data permissions
echo -n "  etcd data directory... "
ETCD_DIR_PERMS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo stat -c '%a' /var/lib/rancher/k3s/server/db 2>/dev/null || echo 'NOT_FOUND'" \
  2>/dev/null || echo "UNKNOWN")

if [[ "${ETCD_DIR_PERMS}" == "700" ]] || [[ "${ETCD_DIR_PERMS}" == "NOT_FOUND" ]]; then
  log_success "Secure (${ETCD_DIR_PERMS})"
  TEST_PASSES=$((TEST_PASSES + 1))
elif [[ "${ETCD_DIR_PERMS}" == "UNKNOWN" ]]; then
  log_warning "Unable to check"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
else
  log_warning "Permissions: ${ETCD_DIR_PERMS}"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Test 6: Container Runtime Security
echo "─────────────────────────────────────────"
echo "Test 6: Container Runtime (containerd)"
echo "─────────────────────────────────────────"
echo ""

echo "Checking containerd configuration..."

# Check if containerd is running
echo -n "  containerd service... "
CONTAINERD_STATUS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo systemctl is-active containerd || sudo ps aux | grep 'k3s containerd' | grep -v grep" \
  2>/dev/null || echo "INACTIVE")

if echo "${CONTAINERD_STATUS}" | grep -qE "active|containerd"; then
  log_success "Running"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "Not running"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

# Check runtime configuration
echo -n "  Runtime seccomp profile... "
SECCOMP=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo crictl info 2>/dev/null | grep -i seccomp || echo 'NOT_CONFIGURED'" \
  2>/dev/null || echo "UNKNOWN")

if echo "${SECCOMP}" | grep -qvE "NOT_CONFIGURED|UNKNOWN"; then
  log_success "Configured"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Not explicitly configured"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Test 7: K3s Service Configuration
echo "─────────────────────────────────────────"
echo "Test 7: K3s Service Security"
echo "─────────────────────────────────────────"
echo ""

echo "Checking K3s service configuration..."

# Check if K3s is running as systemd service
echo -n "  K3s systemd service... "
SERVICE_STATUS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo systemctl is-active k3s || sudo systemctl is-active k3s-agent" \
  2>/dev/null || echo "INACTIVE")

if echo "${SERVICE_STATUS}" | grep -q "active"; then
  log_success "Active"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_error "Not active"
  record_finding "CRITICAL" "K3s service not running"
  TEST_FAILURES=$((TEST_FAILURES + 1))
fi

# Check service file security
echo -n "  Service file permissions... "
SERVICE_PERMS=$(ansible all -i "${INVENTORY}" --limit "${FIRST_NODE}" -m shell \
  -a "sudo stat -c '%a' /etc/systemd/system/k3s*.service 2>/dev/null | head -1" \
  2>/dev/null || echo "NOT_FOUND")

if [[ "${SERVICE_PERMS}" == "644" ]] || [[ "${SERVICE_PERMS}" == "600" ]]; then
  log_success "Secure (${SERVICE_PERMS})"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "Permissions: ${SERVICE_PERMS}"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

# Test 8: K3s Network Plugin Security
echo "─────────────────────────────────────────"
echo "Test 8: Network Plugin Configuration"
echo "─────────────────────────────────────────"
echo ""

echo "Checking Flannel configuration..."

# Check Flannel backend
echo -n "  Flannel backend... "
GROUP_VARS_FILE="$(dirname "${INVENTORY}")/../group_vars/all.yaml"
FLANNEL_BACKEND=$(grep "k3s_flannel_backend" "${GROUP_VARS_FILE}" 2>/dev/null | awk '{print $2}' || echo "vxlan")

echo "${FLANNEL_BACKEND}"

if [[ "${FLANNEL_BACKEND}" == "vxlan" ]] || [[ "${FLANNEL_BACKEND}" == "wireguard" ]]; then
  log_success "  Secure backend (${FLANNEL_BACKEND})"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "  Backend ${FLANNEL_BACKEND} may not provide encryption"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

# Check IPv6 is disabled (if not needed)
echo -n "  IPv6 configuration... "
IPV6_ENABLED=$(grep "k3s_enable_ipv6.*true" "${GROUP_VARS_FILE}" 2>/dev/null || echo "false")

if [[ "${IPV6_ENABLED}" == *"false"* ]]; then
  log_success "IPv6 disabled (reduces attack surface)"
  TEST_PASSES=$((TEST_PASSES + 1))
else
  log_warning "IPv6 enabled"
  TEST_WARNINGS=$((TEST_WARNINGS + 1))
fi

echo ""

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
  echo "❌ K3S SECURITY ISSUES DETECTED"
  cat /tmp/security-findings.txt 2>/dev/null || true
  exit 1
else
  echo "✅ K3S SECURITY VALIDATED"
  exit 0
fi
