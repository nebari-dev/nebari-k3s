#!/usr/bin/env bash
# Quick Docker-based testing for individual roles
# Useful for macOS users or quick syntax validation
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONTAINER_NAME="nebari-test-node"
IMAGE="rockylinux:9"

usage() {
    cat <<EOF
Usage: $0 [command]

Quick Docker-based role testing (useful on macOS)

Commands:
    start       Start a Rocky Linux 9 test container
    stop        Stop and remove the test container
    test-role   Test a specific role (e.g., common, k3s_master)
    shell       Open a shell in the container
    status      Check container status

Examples:
    $0 start
    $0 test-role common
    $0 shell
    $0 stop

Note: This is for syntax/logic testing only. Firewall and networking
      features will be limited in containers.
EOF
    exit 0
}

start_container() {
    echo -e "${BLUE}Starting test container...${NC}"

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${YELLOW}Container already exists, removing...${NC}"
        docker rm -f "${CONTAINER_NAME}" || true
    fi

    docker run -d \
        --name "${CONTAINER_NAME}" \
        --privileged \
        --cap-add=NET_ADMIN \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        "${IMAGE}" \
        /sbin/init

    echo -e "${GREEN}✓ Container started${NC}"
    echo ""
    echo "Container IP: $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}")"
    echo ""
    echo "Create an inventory file:"
    echo "  [test]"
    echo "  ${CONTAINER_NAME} ansible_connection=docker"
}

stop_container() {
    echo -e "${BLUE}Stopping test container...${NC}"
    docker rm -f "${CONTAINER_NAME}" || true
    echo -e "${GREEN}✓ Container removed${NC}"
}

test_role() {
    local role=${1:-}

    if [[ -z "$role" ]]; then
        echo "Error: Role name required"
        echo "Usage: $0 test-role <role_name>"
        echo ""
        echo "Available roles:"
        ls -1 roles/
        exit 1
    fi

    if [[ ! -d "roles/${role}" ]]; then
        echo "Error: Role 'roles/${role}' not found"
        exit 1
    fi

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${YELLOW}Container not running, starting it...${NC}"
        start_container
        echo ""
        sleep 2
    fi

    echo -e "${BLUE}Testing role: ${role}${NC}"
    echo ""

    # Create temporary inventory
    local tmpinv=$(mktemp)
    cat > "$tmpinv" <<EOF
[test]
${CONTAINER_NAME} ansible_connection=docker

[test:vars]
ansible_user=root
EOF

    # Run ansible
    ansible-playbook -i "$tmpinv" -e "ansible_connection=docker" <<EOF
---
- hosts: test
  gather_facts: yes
  roles:
    - role: ${role}
EOF

    rm -f "$tmpinv"

    echo ""
    echo -e "${GREEN}✓ Role test complete${NC}"
}

shell_access() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container not running. Start it with: $0 start"
        exit 1
    fi

    echo -e "${BLUE}Opening shell in container...${NC}"
    docker exec -it "${CONTAINER_NAME}" /bin/bash
}

check_status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${GREEN}✓ Container is running${NC}"
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo -e "${YELLOW}Container is not running${NC}"
    fi
}

# Main
case "${1:-help}" in
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    test-role)
        test_role "${2:-}"
        ;;
    shell)
        shell_access
        ;;
    status)
        check_status
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        usage
        ;;
esac
