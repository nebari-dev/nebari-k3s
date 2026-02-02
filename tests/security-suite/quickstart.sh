#!/usr/bin/env bash
##
## Quick Start Script - Security Test Suite
## Automated setup and execution
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  K3s Security Test Suite - Quick Start${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Check for inventory file
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <inventory.ini> [output-dir]"
  echo ""
  echo "Examples:"
  echo "  $0 ../rocky9/inventories/hosts.ini"
  echo "  $0 ../../inventories/production.ini reports/prod"
  exit 1
fi

INVENTORY="$1"
OUTPUT_DIR="${2:-reports/$(date +%Y%m%d-%H%M%S)}"

if [[ ! -f "${INVENTORY}" ]]; then
  echo -e "${RED}Error: Inventory file not found: ${INVENTORY}${NC}"
  exit 1
fi

echo "Configuration:"
echo "  Inventory: ${INVENTORY}"
echo "  Output:    ${OUTPUT_DIR}"
echo ""

# Step 1: Check dependencies
echo -e "${BLUE}Step 1: Checking dependencies...${NC}"
MISSING_DEPS=()

for cmd in ansible nmap nc jq python3; do
  if ! command -v "${cmd}" &> /dev/null; then
    MISSING_DEPS+=("${cmd}")
  fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  echo -e "${RED}Missing dependencies: ${MISSING_DEPS[*]}${NC}"
  echo ""
  echo "Install with:"
  echo "  sudo dnf install -y ansible nmap nc jq python3"
  echo ""
  exit 1
else
  echo -e "${GREEN}✓ All dependencies installed${NC}"
fi
echo ""

# Step 2: Validate Ansible connectivity
echo -e "${BLUE}Step 2: Validating Ansible connectivity...${NC}"
if ansible all -i "${INVENTORY}" -m ping &>/dev/null; then
  echo -e "${GREEN}✓ Ansible can reach all nodes${NC}"
else
  echo -e "${RED}✗ Ansible connectivity failed${NC}"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check SSH keys are configured"
  echo "  2. Verify inventory file format"
  echo "  3. Test manually: ansible all -i ${INVENTORY} -m ping"
  echo ""
  exit 1
fi
echo ""

# Step 3: Create output directory
echo -e "${BLUE}Step 3: Creating output directory...${NC}"
mkdir -p "${OUTPUT_DIR}"
echo -e "${GREEN}✓ Created: ${OUTPUT_DIR}${NC}"
echo ""

# Step 4: Run security tests
echo -e "${BLUE}Step 4: Running security test suite...${NC}"
echo ""

if "${SCRIPT_DIR}/run-security-tests.sh" -i "${INVENTORY}" -o "${OUTPUT_DIR}"; then
  echo ""
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✓ All Tests Completed Successfully!${NC}"
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  TESTS_PASSED=true
else
  echo ""
  echo -e "${YELLOW}════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  ⚠ Some Tests Failed${NC}"
  echo -e "${YELLOW}════════════════════════════════════════${NC}"
  TESTS_PASSED=false
fi
echo ""

# Step 5: Display results
echo -e "${BLUE}Reports generated:${NC}"
echo "  • JSON Report: ${OUTPUT_DIR}/security-report.json"
echo "  • HTML Report: ${OUTPUT_DIR}/security-report.html"
echo ""

# Show compliance score
if [[ -f "${OUTPUT_DIR}/security-report.json" ]]; then
  SCORE=$(jq -r '.summary.compliance_score' "${OUTPUT_DIR}/security-report.json" 2>/dev/null || echo "0")
  FAILED=$(jq -r '.summary.failed' "${OUTPUT_DIR}/security-report.json" 2>/dev/null || echo "0")
  
  echo -e "${BLUE}Compliance Score: ${SCORE}%${NC}"
  
  if [[ ${SCORE} -ge 90 ]]; then
    echo -e "${GREEN}✓ Excellent - NASA compliant${NC}"
  elif [[ ${SCORE} -ge 75 ]]; then
    echo -e "${YELLOW}⚠ Good - Minor improvements recommended${NC}"
  else
    echo -e "${RED}✗ Needs improvement${NC}"
  fi
  echo ""
  
  # Open HTML report
  if [[ -f "${OUTPUT_DIR}/security-report.html" ]]; then
    echo "View detailed report:"
    echo "  file://${PWD}/${OUTPUT_DIR}/security-report.html"
    echo ""
    
    # Try to open in browser
    if command -v xdg-open &> /dev/null; then
      echo "Opening in browser..."
      xdg-open "${OUTPUT_DIR}/security-report.html" &>/dev/null &
    fi
  fi
fi

# Next steps
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

if [[ "${TESTS_PASSED}" == "true" ]]; then
  echo "✓ Your cluster passes all security tests!"
  echo ""
  echo "To compare with your old cluster:"
  echo "  1. Capture old cluster baseline:"
  echo "     ./capture-baseline.sh <OLD_CLUSTER_IP> old-baseline.json"
  echo ""
  echo "  2. Run comparison:"
  echo "     ./compare-clusters.sh old-baseline.json ${OUTPUT_DIR}/security-report.json --html comparison.html"
  echo ""
else
  echo "⚠ Some tests failed. Review the findings:"
  echo "  • Open: ${OUTPUT_DIR}/security-report.html"
  echo "  • Check: ${OUTPUT_DIR}/*-output.txt for details"
  echo ""
  echo "Address the issues and re-run:"
  echo "  $0 ${INVENTORY} ${OUTPUT_DIR}"
  echo ""
fi

echo "For detailed test information:"
echo "  • Port Exposure:        ${OUTPUT_DIR}/port-exposure-output.txt"
echo "  • Firewall Config:      ${OUTPUT_DIR}/firewall-config-output.txt"
echo "  • Network Segmentation: ${OUTPUT_DIR}/network-segmentation-output.txt"
echo "  • Compliance:           ${OUTPUT_DIR}/compliance-output.txt"
echo "  • K3s Security:         ${OUTPUT_DIR}/k3s-security-output.txt"
echo ""

if [[ "${TESTS_PASSED}" == "true" ]] && [[ ${SCORE} -ge 90 ]]; then
  exit 0
else
  exit 1
fi
