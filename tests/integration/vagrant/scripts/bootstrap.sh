#!/usr/bin/env bash
# Bootstrap script for Vagrant VMs
# Handles both Rocky Linux (no subscription needed) and RHEL (requires subscription)

set -euxo pipefail

# Check if system has package manager access (RHEL requires subscription)
if sudo dnf check-update &>/dev/null || [ $? -eq 100 ]; then
  # Exit code 0 or 100 (updates available) means dnf works
  echo "Package manager accessible, updating system..."
  sudo dnf -y update || echo "Warning: dnf update failed, continuing anyway..."
else
  echo "Warning: Package manager not accessible (RHEL without subscription?)"
  echo "Skipping system update, installing required packages only..."
fi

sudo dnf -y install python3 python3-libselinux firewalld iproute curl jq nmap-ncat || {
  echo "Warning: Some packages failed to install, continuing..."
}

sudo systemctl enable --now firewalld || true
sudo systemctl enable --now sshd || true

# Best-effort static IP (useful on qemu/mac where Vagrant can't inject "private_network")
if [[ -n "${STATIC_IP:-}" ]]; then
  IFACE="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')"
  sudo ip addr add "${STATIC_IP}/24" dev "${IFACE}" || true
  sudo ip link set "${IFACE}" up || true
fi
