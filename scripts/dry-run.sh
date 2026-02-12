#!/usr/bin/env bash
# Ansible Dry-Run Script - Shows what would change without applying
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Dry-run mode for Ansible playbook - shows what would change without applying.

OPTIONS:
    -i, --inventory FILE    Inventory file (required)
    -l, --limit HOSTS       Limit to specific hosts
    -t, --tags TAGS         Run specific tags only
    -s, --skip-tags TAGS    Skip specific tags
    -v, --verbose           Verbose output (-vv for more)
    -o, --output FILE       Save diff output to file
    -h, --help              Show this help message

EXAMPLES:
    # Dry-run against vagrant lab
    $0 -i tests/rocky9/inventories/hosts.ini

    # Check only firewall changes on master nodes
    $0 -i inventory/production.ini -l master -t firewall

    # Verbose dry-run with output saved
    $0 -i inventory/staging.ini -v -o /tmp/dry-run.log

FEATURES:
    - Shows exact changes that would be made
    - No actual modifications to system
    - Displays file diffs for template/config changes
    - Lists packages to install/remove
    - Shows service state changes
    - Exit code 0 = no changes, 2 = changes detected
EOF
    exit 0
}

# Default values
INVENTORY=""
LIMIT=""
TAGS=""
SKIP_TAGS=""
VERBOSE=""
OUTPUT_FILE=""
PLAYBOOK="playbook.yaml"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -l|--limit)
            LIMIT="--limit $2"
            shift 2
            ;;
        -t|--tags)
            TAGS="--tags $2"
            shift 2
            ;;
        -s|--skip-tags)
            SKIP_TAGS="--skip-tags $2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -vv)
            VERBOSE="-vv"
            shift
            ;;
        -vvv)
            VERBOSE="-vvv"
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Check required arguments
if [[ -z "$INVENTORY" ]]; then
    echo -e "${RED}Error: Inventory file is required${NC}"
    echo "Use -i or --inventory to specify inventory file"
    exit 1
fi

if [[ ! -f "$INVENTORY" ]]; then
    echo -e "${RED}Error: Inventory file not found: $INVENTORY${NC}"
    exit 1
fi

if [[ ! -f "$PLAYBOOK" ]]; then
    echo -e "${RED}Error: Playbook not found: $PLAYBOOK${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           ANSIBLE DRY-RUN MODE (CHECK + DIFF)            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Inventory:${NC} $INVENTORY"
echo -e "${YELLOW}Playbook:${NC}  $PLAYBOOK"
[[ -n "$LIMIT" ]] && echo -e "${YELLOW}Limited to:${NC} ${LIMIT#--limit }"
[[ -n "$TAGS" ]] && echo -e "${YELLOW}Tags:${NC} ${TAGS#--tags }"
[[ -n "$SKIP_TAGS" ]] && echo -e "${YELLOW}Skip Tags:${NC} ${SKIP_TAGS#--skip-tags }"
echo ""
echo -e "${GREEN}This will NOT make any changes to your systems${NC}"
echo -e "${GREEN}Running in --check mode with --diff enabled${NC}"
echo ""
echo "───────────────────────────────────────────────────────────"
echo ""

# Build ansible command
ANSIBLE_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK --check --diff $LIMIT $TAGS $SKIP_TAGS $VERBOSE"

# Run with or without output capture
if [[ -n "$OUTPUT_FILE" ]]; then
    echo -e "${BLUE}Saving output to: $OUTPUT_FILE${NC}"
    echo ""
    
    # Run and save, also showing on screen
    $ANSIBLE_CMD 2>&1 | tee "$OUTPUT_FILE"
    EXIT_CODE=${PIPESTATUS[0]}
else
    $ANSIBLE_CMD
    EXIT_CODE=$?
fi

echo ""
echo "───────────────────────────────────────────────────────────"
echo ""

# Interpret exit code
case $EXIT_CODE in
    0)
        echo -e "${GREEN}✓ SUCCESS: No changes detected${NC}"
        echo -e "${GREEN}  All systems are in desired state${NC}"
        ;;
    2)
        echo -e "${YELLOW}⚠ CHANGES DETECTED${NC}"
        echo -e "${YELLOW}  The playbook would make changes to your systems${NC}"
        echo -e "${YELLOW}  Review the diff output above${NC}"
        ;;
    *)
        echo -e "${RED}✗ ERROR: Playbook execution failed (exit code: $EXIT_CODE)${NC}"
        echo -e "${RED}  Check the output above for errors${NC}"
        ;;
esac

echo ""

exit $EXIT_CODE
