#!/bin/bash
#
# K3s Security Validation Script
# 
# This script validates the firewall configuration and security posture
# of your K3s cluster after deployment.
#
# Usage: ./validate-security.sh [node-ip] [admin-ip]
#   node-ip: IP address of a cluster node to test (required)
#   admin-ip: Your IP address for admin access tests (optional)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_fail "This script must be run as root (some tests require it)"
        print_info "Run with: sudo ./validate-security.sh"
        exit 1
    fi
}

# Test port connectivity
test_port() {
    local ip=$1
    local port=$2
    local should_succeed=$3
    local timeout=2
    
    if timeout $timeout nc -z -w 1 $ip $port &>/dev/null; then
        if [ "$should_succeed" = "true" ]; then
            print_pass "Port $port is accessible (expected)"
            return 0
        else
            print_fail "Port $port is accessible (should be blocked)"
            return 1
        fi
    else
        if [ "$should_succeed" = "false" ]; then
            print_pass "Port $port is blocked (expected)"
            return 0
        else
            print_fail "Port $port is blocked (should be accessible)"
            return 1
        fi
    fi
}

# Main validation starts here
main() {
    local NODE_IP=$1
    local ADMIN_IP=$2
    
    if [ -z "$NODE_IP" ]; then
        echo "Usage: $0 <node-ip> [admin-ip]"
        echo "Example: $0 10.11.0.31 10.11.0.100"
        exit 1
    fi
    
    print_header "K3s Security Validation Script"
    print_info "Target node: $NODE_IP"
    [ -n "$ADMIN_IP" ] && print_info "Admin IP: $ADMIN_IP"
    
    # Check if we're running on a cluster node
    RUNNING_ON_NODE=false
    if ip addr show | grep -q "$NODE_IP"; then
        RUNNING_ON_NODE=true
        print_info "Running on cluster node"
    else
        print_info "Running from external host"
    fi
    
    # ========================================
    # Test 1: Firewall Service
    # ========================================
    print_header "Test 1: Firewall Service Status"
    
    if $RUNNING_ON_NODE; then
        print_test "Checking if firewalld is running"
        if systemctl is-active --quiet firewalld; then
            print_pass "firewalld is running"
        else
            print_fail "firewalld is not running"
        fi
        
        print_test "Checking if firewalld is enabled"
        if systemctl is-enabled --quiet firewalld; then
            print_pass "firewalld is enabled"
        else
            print_warn "firewalld is not enabled (won't start on boot)"
        fi
    else
        print_info "Skipping firewalld service checks (not on node)"
    fi
    
    # ========================================
    # Test 2: Firewall Zones
    # ========================================
    print_header "Test 2: Firewall Zones Configuration"
    
    if $RUNNING_ON_NODE; then
        print_test "Checking for k3s-cluster zone"
        if firewall-cmd --get-zones | grep -q "k3s-cluster"; then
            print_pass "k3s-cluster zone exists"
            
            print_test "Checking k3s-cluster zone sources"
            sources=$(firewall-cmd --zone=k3s-cluster --list-sources)
            if [ -n "$sources" ]; then
                print_pass "k3s-cluster zone has sources configured"
                print_info "Sources: $sources"
            else
                print_fail "k3s-cluster zone has no sources"
            fi
        else
            print_fail "k3s-cluster zone does not exist"
        fi
        
        print_test "Checking trusted zone for pod/service subnets"
        trusted_sources=$(firewall-cmd --zone=trusted --list-sources)
        if echo "$trusted_sources" | grep -q "10.42.0.0/16"; then
            print_pass "Pod subnet (10.42.0.0/16) in trusted zone"
        else
            print_fail "Pod subnet (10.42.0.0/16) not in trusted zone"
        fi
        
        if echo "$trusted_sources" | grep -q "10.43.0.0/16"; then
            print_pass "Service subnet (10.43.0.0/16) in trusted zone"
        else
            print_fail "Service subnet (10.43.0.0/16) not in trusted zone"
        fi
    else
        print_info "Skipping zone configuration checks (not on node)"
    fi
    
    # ========================================
    # Test 3: Port Security (from external)
    # ========================================
    print_header "Test 3: Port Security Tests"
    
    if ! $RUNNING_ON_NODE; then
        print_test "Testing sensitive ports (should be blocked)"
        
        # Ports that should always be blocked from external
        BLOCKED_PORTS=(6443 10250 10251 10252 2379 2380 6444 8080 9990)
        
        for port in "${BLOCKED_PORTS[@]}"; do
            test_port "$NODE_IP" "$port" "false"
        done
        
        print_test "Testing SSH port (22)"
        if [ -n "$ADMIN_IP" ]; then
            my_ip=$(curl -s ifconfig.me 2>/dev/null || echo "")
            if [ "$my_ip" = "$ADMIN_IP" ]; then
                test_port "$NODE_IP" "22" "true"
            else
                print_info "Not testing from admin IP, SSH might be blocked"
            fi
        else
            print_info "Admin IP not provided, skipping SSH test"
        fi
        
        print_test "Testing ingress ports (80/443)"
        test_port "$NODE_IP" "80" "true" || print_info "Port 80 blocked (might be intentional)"
        test_port "$NODE_IP" "443" "true" || print_info "Port 443 blocked (might be intentional)"
        
        print_test "Testing NodePort range (should be blocked)"
        # Test a few random NodePorts
        for port in 30000 30806 31000 32000; do
            test_port "$NODE_IP" "$port" "false"
        done
    else
        print_info "Skipping external port tests (running on node)"
    fi
    
    # ========================================
    # Test 4: K3s Service Status
    # ========================================
    print_header "Test 4: K3s Service Status"
    
    if $RUNNING_ON_NODE; then
        print_test "Checking K3s services"
        
        if systemctl is-active --quiet k3s 2>/dev/null; then
            print_pass "k3s (master) service is running"
        elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
            print_pass "k3s-agent (worker) service is running"
        else
            print_fail "No K3s service is running"
        fi
        
        print_test "Checking kubectl connectivity"
        if command -v kubectl &>/dev/null; then
            if kubectl get nodes &>/dev/null; then
                print_pass "kubectl can connect to API"
                node_count=$(kubectl get nodes --no-headers | wc -l)
                print_info "Cluster has $node_count node(s)"
            else
                print_fail "kubectl cannot connect to API"
            fi
        else
            print_info "kubectl not available on this node"
        fi
    else
        print_info "Skipping K3s service checks (not on node)"
    fi
    
    # ========================================
    # Test 5: Listening Ports
    # ========================================
    print_header "Test 5: Listening Ports Analysis"
    
    if $RUNNING_ON_NODE; then
        print_test "Checking listening ports"
        listening=$(ss -tlnp | grep LISTEN)
        
        # Check for expected ports
        expected_ports=(6443 10250)
        for port in "${expected_ports[@]}"; do
            if echo "$listening" | grep -q ":$port "; then
                print_pass "Port $port is listening (expected)"
            else
                print_warn "Port $port is not listening (might be a problem)"
            fi
        done
        
        # Check for unexpected public listeners
        unexpected_public=(2379 2380 10251 10252 8080)
        for port in "${unexpected_public[@]}"; do
            if echo "$listening" | grep -q "0.0.0.0:$port "; then
                print_fail "Port $port is listening on 0.0.0.0 (security risk!)"
            else
                print_pass "Port $port is not listening on 0.0.0.0"
            fi
        done
        
        print_info "\nAll listening ports:"
        ss -tlnp | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -n | uniq
    else
        print_info "Skipping listening ports check (not on node)"
    fi
    
    # ========================================
    # Test 6: Public Zone Rules
    # ========================================
    print_header "Test 6: Public Zone Security Rules"
    
    if $RUNNING_ON_NODE; then
        print_test "Checking for port blocking rules in public zone"
        
        rich_rules=$(firewall-cmd --zone=public --list-rich-rules)
        
        # Check for specific blocking rules
        critical_blocks=(6443 10250 2379)
        for port in "${critical_blocks[@]}"; do
            if echo "$rich_rules" | grep -q "port=\"$port\".*reject"; then
                print_pass "Port $port has reject rule in public zone"
            else
                print_warn "Port $port does not have explicit reject rule"
            fi
        done
        
        # Check for NodePort blocking
        if echo "$rich_rules" | grep -q "port=\"30000-32767\".*reject"; then
            print_pass "NodePort range has reject rule"
        else
            print_warn "NodePort range does not have explicit reject rule"
        fi
        
        print_info "\nAll public zone rich rules:"
        echo "$rich_rules"
    else
        print_info "Skipping public zone checks (not on node)"
    fi
    
    # ========================================
    # Test 7: Network Configuration
    # ========================================
    print_header "Test 7: Network Configuration"
    
    if $RUNNING_ON_NODE; then
        print_test "Checking IP forwarding"
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
            print_pass "IP forwarding is enabled"
        else
            print_fail "IP forwarding is disabled"
        fi
        
        print_test "Checking bridge netfilter"
        if [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null)" = "1" ]; then
            print_pass "bridge-nf-call-iptables is enabled"
        else
            print_warn "bridge-nf-call-iptables is not enabled"
        fi
        
        print_test "Checking CNI network"
        if ip addr show | grep -q "flannel\|cni"; then
            print_pass "CNI network interface found"
        else
            print_warn "No CNI network interface found"
        fi
    else
        print_info "Skipping network configuration checks (not on node)"
    fi
    
    # ========================================
    # Test 8: SELinux Status
    # ========================================
    print_header "Test 8: SELinux Status"
    
    if $RUNNING_ON_NODE; then
        if command -v getenforce &>/dev/null; then
            selinux_status=$(getenforce)
            print_info "SELinux status: $selinux_status"
            
            if [ "$selinux_status" = "Enforcing" ]; then
                print_pass "SELinux is in enforcing mode (most secure)"
            elif [ "$selinux_status" = "Permissive" ]; then
                print_warn "SELinux is in permissive mode (logs but doesn't block)"
            else
                print_info "SELinux is disabled"
            fi
        else
            print_info "SELinux not available on this system"
        fi
    else
        print_info "Skipping SELinux check (not on node)"
    fi
    
    # ========================================
    # Summary
    # ========================================
    print_header "Validation Summary"
    
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All critical security tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some security tests failed. Review the output above.${NC}"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    for cmd in nc timeout; do
        if ! command -v $cmd &>/dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_fail "Missing required commands: ${missing[*]}"
        print_info "Install with: yum install nc coreutils"
        exit 1
    fi
}

# Run the script
check_dependencies
main "$@"
