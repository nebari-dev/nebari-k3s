#!/usr/bin/env bash
set -euxo pipefail

sudo dnf -y update
sudo dnf -y install python3 python3-libselinux firewalld iproute curl jq nmap-ncat

sudo systemctl enable --now firewalld || true
sudo systemctl enable --now sshd || true

# Best-effort static IP (useful on qemu/mac where Vagrant can't inject "private_network")
if [[ -n "${STATIC_IP:-}" ]]; then
  IFACE="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')"
  sudo ip addr add "${STATIC_IP}/24" dev "${IFACE}" || true
  sudo ip link set "${IFACE}" up || true
fi
