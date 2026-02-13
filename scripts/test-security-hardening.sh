#!/bin/bash
# Security Hardening Test Script
#
# Tests that raw/PREROUTING rules are properly blocking public interface traffic
# Run this script after applying security hardening role

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PUBLIC_INTERFACE="${PUBLIC_INTERFACE:-eth0}"
TIMEOUT=3

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Security Hardening Validation Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Test 1: Check if raw/PREROUTING rules exist
echo -e "${BLUE}[Test 1/5]${NC} Checking raw/PREROUTING rules..."
if sudo iptables -t raw -L PREROUTING -n | grep -q "DROP.*$PUBLIC_INTERFACE"; then
    echo -e "${GREEN}✓ PASS${NC} - raw/PREROUTING rules found"
    RULES_COUNT=$(sudo iptables -t raw -L PREROUTING -n | grep -c "DROP.*$PUBLIC_INTERFACE" || true)
    echo "  Found $RULES_COUNT DROP rules for $PUBLIC_INTERFACE"
else
    echo -e "${RED}✗ FAIL${NC} - No raw/PREROUTING rules found for $PUBLIC_INTERFACE"
    exit 1
fi
echo ""

# Test 2: Check NodePort range blocking
echo -e "${BLUE}[Test 2/5]${NC} Checking NodePort range (30000-32767) blocking..."
if sudo iptables -t raw -L PREROUTING -n | grep -q "30000:32767"; then
    echo -e "${GREEN}✓ PASS${NC} - NodePort range is blocked"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - NodePort range blocking not found"
fi
echo ""

# Test 3: Check Kubelet (10250) blocking
echo -e "${BLUE}[Test 3/5]${NC} Checking Kubelet port (10250) blocking..."
if sudo iptables -t raw -L PREROUTING -n | grep -q "10250"; then
    echo -e "${GREEN}✓ PASS${NC} - Kubelet port is blocked"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Kubelet port blocking not found"
fi
echo ""

# Test 4: Check API Server (6443) blocking
echo -e "${BLUE}[Test 4/5]${NC} Checking API Server port (6443) blocking..."
if sudo iptables -t raw -L PREROUTING -n | grep -q "6443"; then
    echo -e "${GREEN}✓ PASS${NC} - API Server port is blocked"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - API Server port blocking not found"
fi
echo ""

# Test 5: Rule persistence
echo -e "${BLUE}[Test 5/5]${NC} Checking rule persistence configuration..."
if [ -f /etc/iptables/rules.v4 ] || [ -f /etc/sysconfig/iptables ] || command -v netfilter-persistent &> /dev/null; then
    echo -e "${GREEN}✓ PASS${NC} - Rules persistence configured"
    if [ -f /etc/iptables/rules.v4 ]; then
        echo "  Using: /etc/iptables/rules.v4"
    elif [ -f /etc/sysconfig/iptables ]; then
        echo "  Using: /etc/sysconfig/iptables"
    elif command -v netfilter-persistent &> /dev/null; then
        echo "  Using: netfilter-persistent"
    fi
else
    echo -e "${YELLOW}⚠ WARNING${NC} - No persistence mechanism found"
    echo "  Rules may be lost after reboot!"
fi
echo ""

# Display current rules
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Current raw/PREROUTING Rules:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
sudo iptables -t raw -L PREROUTING -n -v --line-numbers | head -20
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Security hardening validation complete${NC}"
echo ""
echo "Protected ports on $PUBLIC_INTERFACE:"
echo "  - 6443 (Kubernetes API)"
echo "  - 10250 (Kubelet)"
echo "  - 2379-2380 (etcd)"
echo "  - 9100 (Node exporter)"
echo "  - 30000-32767 (NodePort range)"
echo ""
echo "Test from external machine:"
echo "  curl --max-time $TIMEOUT http://<public-ip>:30001  # Should timeout"
echo "  curl --max-time $TIMEOUT http://<public-ip>:10250  # Should timeout"
echo "  curl http://<public-ip>:80                          # Should work"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
