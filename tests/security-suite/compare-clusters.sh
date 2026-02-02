#!/usr/bin/env bash
##
## Cluster Comparison Tool
## Compare security posture before and after hardening
##

set -euo pipefail

OLD_REPORT="${1:?Usage: $0 <old-report.json> <new-report.json> [--html output.html]}"
NEW_REPORT="${2:?Usage: $0 <old-report.json> <new-report.json> [--html output.html]}"
HTML_OUTPUT=""

# Parse optional HTML output argument
if [[ $# -ge 4 ]] && [[ "$3" == "--html" ]]; then
  HTML_OUTPUT="$4"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "════════════════════════════════════════"
echo "  Security Cluster Comparison"
echo "════════════════════════════════════════"
echo ""

if [[ ! -f "${OLD_REPORT}" ]]; then
  echo -e "${RED}Error: Old report not found: ${OLD_REPORT}${NC}"
  exit 1
fi

if [[ ! -f "${NEW_REPORT}" ]]; then
  echo -e "${RED}Error: New report not found: ${NEW_REPORT}${NC}"
  exit 1
fi

# Extract key metrics using jq
OLD_SCORE=$(jq -r '.summary.compliance_score // 0' "${OLD_REPORT}")
NEW_SCORE=$(jq -r '.summary.compliance_score // 0' "${NEW_REPORT}")

OLD_PASSED=$(jq -r '.summary.passed // 0' "${OLD_REPORT}")
NEW_PASSED=$(jq -r '.summary.passed // 0' "${NEW_REPORT}")

OLD_FAILED=$(jq -r '.summary.failed // 0' "${OLD_REPORT}")
NEW_FAILED=$(jq -r '.summary.failed // 0' "${NEW_REPORT}")

OLD_FINDINGS=$(jq -r '.findings | length' "${OLD_REPORT}")
NEW_FINDINGS=$(jq -r '.findings | length' "${NEW_REPORT}")

# Calculate deltas
SCORE_DELTA=$((NEW_SCORE - OLD_SCORE))
PASSED_DELTA=$((NEW_PASSED - OLD_PASSED))
FAILED_DELTA=$((NEW_FAILED - OLD_FAILED))
FINDINGS_DELTA=$((NEW_FINDINGS - OLD_FINDINGS))

# Print comparison
echo "Compliance Score:"
echo "  Before: ${OLD_SCORE}%"
echo "  After:  ${NEW_SCORE}%"
if [[ ${SCORE_DELTA} -gt 0 ]]; then
  echo -e "  Change: ${GREEN}+${SCORE_DELTA}% ↑${NC} (IMPROVED)"
elif [[ ${SCORE_DELTA} -lt 0 ]]; then
  echo -e "  Change: ${RED}${SCORE_DELTA}% ↓${NC} (DEGRADED)"
else
  echo "  Change: No change"
fi
echo ""

echo "Tests Passed:"
echo "  Before: ${OLD_PASSED}"
echo "  After:  ${NEW_PASSED}"
if [[ ${PASSED_DELTA} -gt 0 ]]; then
  echo -e "  Change: ${GREEN}+${PASSED_DELTA} ↑${NC}"
elif [[ ${PASSED_DELTA} -lt 0 ]]; then
  echo -e "  Change: ${RED}${PASSED_DELTA} ↓${NC}"
else
  echo "  Change: No change"
fi
echo ""

echo "Tests Failed:"
echo "  Before: ${OLD_FAILED}"
echo "  After:  ${NEW_FAILED}"
if [[ ${FAILED_DELTA} -lt 0 ]]; then
  echo -e "  Change: ${GREEN}${FAILED_DELTA} ↓${NC} (IMPROVED)"
elif [[ ${FAILED_DELTA} -gt 0 ]]; then
  echo -e "  Change: ${RED}+${FAILED_DELTA} ↑${NC} (WORSE)"
else
  echo "  Change: No change"
fi
echo ""

echo "Security Findings:"
echo "  Before: ${OLD_FINDINGS}"
echo "  After:  ${NEW_FINDINGS}"
if [[ ${FINDINGS_DELTA} -lt 0 ]]; then
  echo -e "  Change: ${GREEN}${FINDINGS_DELTA} ↓${NC} (IMPROVED)"
elif [[ ${FINDINGS_DELTA} -gt 0 ]]; then
  echo -e "  Change: ${RED}+${FINDINGS_DELTA} ↑${NC} (NEW FINDINGS)"
else
  echo "  Change: No change"
fi
echo ""

# Overall assessment
echo "════════════════════════════════════════"
echo "  Assessment"
echo "════════════════════════════════════════"
echo ""

if [[ ${SCORE_DELTA} -ge 10 ]] && [[ ${FAILED_DELTA} -le 0 ]]; then
  echo -e "${GREEN}✓ SIGNIFICANT IMPROVEMENT${NC}"
  echo "The security hardening has substantially improved the cluster's security posture."
  echo "Ready for production migration."
elif [[ ${SCORE_DELTA} -gt 0 ]]; then
  echo -e "${GREEN}✓ IMPROVEMENT${NC}"
  echo "Security posture has improved."
elif [[ ${SCORE_DELTA} -eq 0 ]] && [[ ${NEW_SCORE} -ge 90 ]]; then
  echo -e "${GREEN}✓ MAINTAINED EXCELLENT SECURITY${NC}"
  echo "Cluster maintains excellent security compliance."
elif [[ ${SCORE_DELTA} -lt 0 ]]; then
  echo -e "${RED}✗ SECURITY DEGRADATION${NC}"
  echo "Warning: Security posture has degraded. Review changes before migration."
else
  echo -e "${YELLOW}⚠ NO SIGNIFICANT CHANGE${NC}"
  echo "Security posture has not changed significantly."
fi
echo ""

# Detailed comparison by category
echo "════════════════════════════════════════"
echo "  Category Breakdown"
echo "════════════════════════════════════════"
echo ""

CATEGORIES=("port_exposure" "firewall_config" "network_segmentation" "compliance" "k3s_security")
CATEGORY_NAMES=("Port Exposure" "Firewall Config" "Network Segmentation" "Compliance" "K3s Security")

for i in "${!CATEGORIES[@]}"; do
  category="${CATEGORIES[$i]}"
  name="${CATEGORY_NAMES[$i]}"
  
  old_passed=$(jq -r ".test_results.${category}.passed // 0" "${OLD_REPORT}")
  new_passed=$(jq -r ".test_results.${category}.passed // 0" "${NEW_REPORT}")
  
  old_failed=$(jq -r ".test_results.${category}.failed // 0" "${OLD_REPORT}")
  new_failed=$(jq -r ".test_results.${category}.failed // 0" "${NEW_REPORT}")
  
  delta=$((new_passed - old_passed))
  
  echo -n "${name}: "
  if [[ ${delta} -gt 0 ]]; then
    echo -e "${GREEN}+${delta} tests passing${NC}"
  elif [[ ${delta} -lt 0 ]]; then
    echo -e "${RED}${delta} tests failing${NC}"
  else
    echo "No change (${new_passed}/${$((new_passed + new_failed))} passing)"
  fi
done
echo ""

# Generate HTML comparison if requested
if [[ -n "${HTML_OUTPUT}" ]]; then
  echo "Generating HTML comparison report..."
  
  cat > "${HTML_OUTPUT}" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Security Comparison Report</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 1000px; margin: 40px auto; padding: 20px; }
        h1 { color: #0066cc; }
        .comparison { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .metric { background: #f5f5f5; padding: 20px; border-radius: 8px; }
        .metric h3 { margin-top: 0; color: #333; }
        .value { font-size: 36px; font-weight: bold; margin: 10px 0; }
        .delta { font-size: 18px; margin: 10px 0; }
        .improved { color: #28a745; }
        .degraded { color: #dc3545; }
        .unchanged { color: #6c757d; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #0066cc; color: white; }
    </style>
</head>
<body>
    <h1>Security Comparison Report</h1>
EOF

  # Add metrics using variables
  cat >> "${HTML_OUTPUT}" <<HTMLEOF
    <div class="comparison">
        <div class="metric">
            <h3>Compliance Score</h3>
            <div class="value">${NEW_SCORE}%</div>
            <div class="delta $([ ${SCORE_DELTA} -gt 0 ] && echo 'improved' || ([ ${SCORE_DELTA} -lt 0 ] && echo 'degraded' || echo 'unchanged'))">
                ${SCORE_DELTA:+$([ ${SCORE_DELTA} -gt 0 ] && echo "+")${SCORE_DELTA}% change}
            </div>
            <small>Before: ${OLD_SCORE}%</small>
        </div>
        <div class="metric">
            <h3>Tests Passed</h3>
            <div class="value">${NEW_PASSED}</div>
            <div class="delta $([ ${PASSED_DELTA} -gt 0 ] && echo 'improved' || ([ ${PASSED_DELTA} -lt 0 ] && echo 'degraded' || echo 'unchanged'))">
                ${PASSED_DELTA:+$([ ${PASSED_DELTA} -gt 0 ] && echo "+")${PASSED_DELTA} change}
            </div>
            <small>Before: ${OLD_PASSED}</small>
        </div>
        <div class="metric">
            <h3>Tests Failed</h3>
            <div class="value">${NEW_FAILED}</div>
            <div class="delta $([ ${FAILED_DELTA} -lt 0 ] && echo 'improved' || ([ ${FAILED_DELTA} -gt 0 ] && echo 'degraded' || echo 'unchanged'))">
                ${FAILED_DELTA:+$([ ${FAILED_DELTA} -gt 0 ] && echo "+")${FAILED_DELTA} change}
            </div>
            <small>Before: ${OLD_FAILED}</small>
        </div>
        <div class="metric">
            <h3>Findings</h3>
            <div class="value">${NEW_FINDINGS}</div>
            <div class="delta $([ ${FINDINGS_DELTA} -lt 0 ] && echo 'improved' || ([ ${FINDINGS_DELTA} -gt 0 ] && echo 'degraded' || echo 'unchanged'))">
                ${FINDINGS_DELTA:+$([ ${FINDINGS_DELTA} -gt 0 ] && echo "+")${FINDINGS_DELTA} change}
            </div>
            <small>Before: ${OLD_FINDINGS}</small>
        </div>
    </div>

    <h2>Summary</h2>
HTMLEOF

  if [[ ${SCORE_DELTA} -ge 10 ]]; then
    echo '<p class="improved">✓ Significant security improvement detected. Cluster is ready for migration.</p>' >> "${HTML_OUTPUT}"
  elif [[ ${SCORE_DELTA} -gt 0 ]]; then
    echo '<p class="improved">✓ Security posture has improved.</p>' >> "${HTML_OUTPUT}"
  elif [[ ${SCORE_DELTA} -lt 0 ]]; then
    echo '<p class="degraded">✗ Security posture has degraded. Review before migration.</p>' >> "${HTML_OUTPUT}"
  else
    echo '<p class="unchanged">No significant change in security posture.</p>' >> "${HTML_OUTPUT}"
  fi

  echo "</body></html>" >> "${HTML_OUTPUT}"
  
  echo -e "${GREEN}✓${NC} HTML report generated: ${HTML_OUTPUT}"
fi

echo ""
echo "════════════════════════════════════════"

# Exit code based on improvement
if [[ ${SCORE_DELTA} -ge 10 ]] && [[ ${NEW_SCORE} -ge 90 ]]; then
  exit 0  # Excellent improvement
elif [[ ${SCORE_DELTA} -ge 0 ]]; then
  exit 0  # Any improvement is good
else
  exit 1  # Degradation
fi
