#!/usr/bin/env bash
##
## Security Test Suite Runner
## Executes all security validation tests and generates NASA compliance reports
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Default values
INVENTORY=""
OUTPUT_DIR="reports"
VERBOSE=0
QUICK_MODE=0
SKIP_COMPLIANCE=0
PARALLEL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Run comprehensive security tests against K3s cluster and generate compliance reports.

OPTIONS:
  -i, --inventory FILE      Ansible inventory file (required)
  -o, --output-dir DIR      Output directory for reports (default: reports)
  -v, --verbose             Verbose output
  -q, --quick               Quick mode (skip long-running tests)
  -s, --skip-compliance     Skip CIS/NIST compliance tests
  -p, --parallel            Run tests in parallel where possible
  -h, --help                Show this help message

EXAMPLES:
  # Test Rocky9 vagrant lab
  $0 -i ../rocky9/hosts.ini

  # Test production cluster with verbose output
  $0 -i ../../inventories/production.ini -o reports/prod -v

  # Quick security check
  $0 -i ../rocky9/hosts.ini -q

EOF
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--inventory)
      INVENTORY="$2"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -q|--quick)
      QUICK_MODE=1
      shift
      ;;
    -s|--skip-compliance)
      SKIP_COMPLIANCE=1
      shift
      ;;
    -p|--parallel)
      PARALLEL=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "${INVENTORY}" ]]; then
  echo -e "${RED}Error: Inventory file required${NC}"
  usage
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo -e "${RED}Error: Inventory file not found: ${INVENTORY}${NC}"
  exit 1
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"
REPORT_FILE="${OUTPUT_DIR}/security-report.json"
HTML_REPORT="${OUTPUT_DIR}/security-report.html"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  K3s Security Test Suite - NASA Compliance Validation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Inventory:    ${INVENTORY}"
echo "Output Dir:   ${OUTPUT_DIR}"
echo "Quick Mode:   $([ ${QUICK_MODE} -eq 1 ] && echo 'Yes' || echo 'No')"
echo "Parallel:     $([ ${PARALLEL} -eq 1 ] && echo 'Yes' || echo 'No')"
echo "Timestamp:    ${TIMESTAMP}"
echo ""

# Initialize report structure
cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "inventory": "${INVENTORY}",
  "test_results": {
    "port_exposure": {},
    "firewall_config": {},
    "network_segmentation": {},
    "compliance": {},
    "k3s_security": {}
  },
  "summary": {
    "total_tests": 0,
    "passed": 0,
    "failed": 0,
    "warnings": 0,
    "skipped": 0
  },
  "findings": [],
  "compliance_score": 0
}
EOF

echo -e "${GREEN}✓${NC} Initialized report: ${REPORT_FILE}"
echo ""

# Test execution wrapper
run_test_suite() {
  local test_name="$1"
  local test_script="$2"
  local category="$3"
  
  echo -e "${BLUE}━━━ Running: ${test_name} ━━━${NC}"
  
  if [[ ! -f "${test_script}" ]]; then
    echo -e "${YELLOW}⚠${NC}  Test script not found: ${test_script}"
    return 1
  fi
  
  local test_output="${OUTPUT_DIR}/${category}-output.txt"
  local test_json="${OUTPUT_DIR}/${category}-results.json"
  
  if bash "${test_script}" "${INVENTORY}" > "${test_output}" 2>&1; then
    echo -e "${GREEN}✓${NC} ${test_name} - PASSED"
    return 0
  else
    echo -e "${RED}✗${NC} ${test_name} - FAILED"
    if [[ ${VERBOSE} -eq 1 ]]; then
      echo "--- Output ---"
      tail -20 "${test_output}"
      echo "-------------"
    fi
    return 1
  fi
}

# Track overall results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# 1. Port Exposure Tests
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 1: Port Exposure Tests            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

if run_test_suite "Port Exposure Audit" "tests/01-port-exposure.sh" "port-exposure"; then
  ((PASSED_TESTS++))
else
  ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))
echo ""

# 2. Firewall Configuration Tests
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 2: Firewall Configuration Tests   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

if run_test_suite "Firewall Zone Configuration" "tests/02-firewall-config.sh" "firewall-config"; then
  ((PASSED_TESTS++))
else
  ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))
echo ""

# 3. Network Segmentation Tests
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 3: Network Segmentation Tests     ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

if run_test_suite "Network Segmentation" "tests/03-network-segmentation.sh" "network-segmentation"; then
  ((PASSED_TESTS++))
else
  ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))
echo ""

# 4. Compliance Tests (CIS + NIST)
if [[ ${SKIP_COMPLIANCE} -eq 0 ]]; then
  echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  Phase 4: Compliance Tests (CIS/NIST)    ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
  echo ""
  
  if run_test_suite "CIS & NIST Compliance" "tests/04-compliance.sh" "compliance"; then
    ((PASSED_TESTS++))
  else
    ((FAILED_TESTS++))
  fi
  ((TOTAL_TESTS++))
  echo ""
else
  echo -e "${YELLOW}⚠${NC}  Skipping compliance tests"
  echo ""
fi

# 5. K3s-Specific Security Tests
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 5: K3s Security Tests              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

if run_test_suite "K3s Security Configuration" "tests/05-k3s-security.sh" "k3s-security"; then
  ((PASSED_TESTS++))
else
  ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))
echo ""

# Generate consolidated report
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Generating Reports                       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

python3 lib/generate-report.py \
  --output-dir "${OUTPUT_DIR}" \
  --inventory "${INVENTORY}" \
  --timestamp "${TIMESTAMP}"

echo -e "${GREEN}✓${NC} Generated JSON report: ${REPORT_FILE}"
echo -e "${GREEN}✓${NC} Generated HTML report: ${HTML_REPORT}"
echo ""

# Calculate compliance score
COMPLIANCE_SCORE=0
if [[ ${TOTAL_TESTS} -gt 0 ]]; then
  COMPLIANCE_SCORE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
fi

# Print summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Total Tests:       ${TOTAL_TESTS}"
echo -e "Passed:            ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed:            ${RED}${FAILED_TESTS}${NC}"
echo -e "Warnings:          ${YELLOW}${WARNING_TESTS}${NC}"
echo ""
echo -e "Compliance Score:  ${COMPLIANCE_SCORE}%"
echo ""

# Determine exit status
if [[ ${FAILED_TESTS} -eq 0 ]]; then
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✓ ALL TESTS PASSED - Cluster is NASA compliant${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
  exit 0
elif [[ ${COMPLIANCE_SCORE} -ge 90 ]]; then
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  ⚠ TESTS PASSED WITH WARNINGS${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Review findings in: ${HTML_REPORT}"
  exit 0
else
  echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}  ✗ TESTS FAILED - Security issues detected${NC}"
  echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Critical findings detected. Review report: ${HTML_REPORT}"
  exit 1
fi
