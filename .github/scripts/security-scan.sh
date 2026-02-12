#!/usr/bin/env bash
set -euo pipefail

INV="${1:?Usage: security-scan.sh <inventory.ini>}"

# Collect target IPs from ansible_host=
IPS="$(awk '/ansible_host=/{for(i=1;i<=NF;i++) if($i ~ /ansible_host=/){sub("ansible_host=","",$i); print $i}}' "${INV}" | sort -u)"

echo "Targets:"
echo "${IPS}"

# Host-side scan (fast)
if command -v nmap >/dev/null 2>&1; then
  for ip in ${IPS}; do
    echo "== nmap ${ip} =="
    nmap -Pn -sS -sV -p 22,80,443,6443,8472,10250,51820,7946 "${ip}" || true
  done
else
  echo "nmap not found; skipping host-side nmap scan"
fi

# Also capture remote state via ssh (uses vagrant user by default)
# If you use a different user/key, set ANSIBLE_SSH_USER / ANSIBLE_PRIVATE_KEY_FILE.
USER="${ANSIBLE_SSH_USER:-vagrant}"

for ip in ${IPS}; do
  echo "== remote checks ${ip} =="
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${USER}@${ip}" \
    'sudo ss -tulpn; (sudo firewall-cmd --state && sudo firewall-cmd --list-all) || true; (sudo ufw status verbose) || true' \
    || true
done
