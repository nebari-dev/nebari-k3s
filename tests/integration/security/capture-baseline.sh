#!/usr/bin/env bash
##
## Capture Security Baseline
## Captures current cluster state for before/after comparison
##

set -euo pipefail

CLUSTER_IP="${1:?Usage: $0 <cluster-ip>}"
OUTPUT_FILE="${2:-baseline-$(date +%Y%m%d-%H%M%S).json}"

echo "════════════════════════════════════════"
echo "  Capturing Security Baseline"
echo "════════════════════════════════════════"
echo ""
echo "Target:     ${CLUSTER_IP}"
echo "Output:     ${OUTPUT_FILE}"
echo ""

# Check dependencies
for cmd in nmap nc jq; do
  if ! command -v "${cmd}" &> /dev/null; then
    echo "Error: ${cmd} not found. Please install it first."
    exit 1
  fi
done

# Initialize JSON structure
cat > "${OUTPUT_FILE}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cluster_ip": "${CLUSTER_IP}",
  "port_scan": {},
  "exposed_services": [],
  "firewall_state": "unknown",
  "security_score": 0
}
EOF

echo "1/5 Scanning ports..."

# Scan critical Kubernetes ports
SCAN_RESULTS=$(nmap -Pn -sV -p 22,80,443,6443,2379,2380,8472,10250,30000-30010 "${CLUSTER_IP}" 2>/dev/null || echo "SCAN_FAILED")

if [[ "${SCAN_RESULTS}" != "SCAN_FAILED" ]]; then
  # Parse open ports
  OPEN_PORTS=$(echo "${SCAN_RESULTS}" | grep "open" | awk '{print $1}' | sed 's|/tcp||g' | tr '\n' ',' | sed 's/,$//')
  echo "  Open ports: ${OPEN_PORTS:-none}"
  
  # Check critical ports
  CRITICAL_EXPOSED=0
  for port in 6443 10250 2379 2380; do
    if echo "${SCAN_RESULTS}" | grep -q "${port}/tcp.*open"; then
      echo "  ⚠ Critical port ${port} is OPEN"
      CRITICAL_EXPOSED=$((CRITICAL_EXPOSED + 1))
    fi
  done
  
  # Store in JSON
  jq --arg ports "${OPEN_PORTS}" '.port_scan.open_ports = $ports' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
  jq --argjson critical ${CRITICAL_EXPOSED} '.port_scan.critical_exposed = $critical' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
else
  echo "  Port scan failed"
fi

echo ""
echo "2/5 Checking API server accessibility..."

if timeout 5 nc -zv "${CLUSTER_IP}" 6443 2>&1 | grep -q "succeeded\|open\|connected"; then
  echo "  ⚠ API server (6443) is accessible"
  jq '.exposed_services += ["api-server"]' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
else
  echo "  ✓ API server blocked"
fi

echo ""
echo "3/5 Checking kubelet accessibility..."

if timeout 5 nc -zv "${CLUSTER_IP}" 10250 2>&1 | grep -q "succeeded\|open\|connected"; then
  echo "  ⚠ Kubelet (10250) is accessible"
  jq '.exposed_services += ["kubelet"]' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
else
  echo "  ✓ Kubelet blocked"
fi

echo ""
echo "4/5 Checking etcd accessibility..."

ETCD_OPEN=0
for port in 2379 2380; do
  if timeout 5 nc -zv "${CLUSTER_IP}" "${port}" 2>&1 | grep -q "succeeded\|open\|connected"; then
    echo "  ⚠ etcd (${port}) is accessible"
    jq '.exposed_services += ["etcd-'${port}'"]' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
    ETCD_OPEN=$((ETCD_OPEN + 1))
  fi
done

if [[ ${ETCD_OPEN} -eq 0 ]]; then
  echo "  ✓ etcd ports blocked"
fi

echo ""
echo "5/5 Calculating security score..."

# Calculate score based on what's NOT exposed
TOTAL_CHECKS=4  # API, kubelet, etcd-client, etcd-peer
EXPOSED_COUNT=$(jq '.exposed_services | length' "${OUTPUT_FILE}")
PASSED=$((TOTAL_CHECKS - EXPOSED_COUNT))
SCORE=$((PASSED * 100 / TOTAL_CHECKS))

jq --argjson score ${SCORE} '.security_score = $score' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
jq --argjson passed ${PASSED} '.summary.passed = $passed' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"
jq --argjson failed ${EXPOSED_COUNT} '.summary.failed = $failed' "${OUTPUT_FILE}" > /tmp/baseline.tmp && mv /tmp/baseline.tmp "${OUTPUT_FILE}"

echo "  Security score: ${SCORE}%"
echo ""

echo "════════════════════════════════════════"
echo "  Baseline Summary"
echo "════════════════════════════════════════"
echo ""
echo "Timestamp:        $(jq -r '.timestamp' "${OUTPUT_FILE}")"
echo "Cluster IP:       ${CLUSTER_IP}"
echo "Security Score:   ${SCORE}%"
echo "Exposed Services: ${EXPOSED_COUNT}"
echo ""

if [[ ${EXPOSED_COUNT} -gt 0 ]]; then
  echo "⚠ Exposed services:"
  jq -r '.exposed_services[]' "${OUTPUT_FILE}" | while read -r service; do
    echo "  - ${service}"
  done
  echo ""
fi

echo "✓ Baseline saved to: ${OUTPUT_FILE}"
echo ""

if [[ ${SCORE} -lt 75 ]]; then
  echo "⚠ Security score is low. Consider applying security hardening."
  exit 1
elif [[ ${SCORE} -lt 90 ]]; then
  echo "⚠ Security score could be improved."
  exit 0
else
  echo "✓ Good security posture."
  exit 0
fi
