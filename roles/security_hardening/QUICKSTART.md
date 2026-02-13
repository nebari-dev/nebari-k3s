# Security Hardening - Quick Start

## TL;DR

```bash
# Apply security hardening
ansible-playbook -i inventory.ini security-hardening.yaml

# Test it works
sudo iptables -t raw -L PREROUTING -n
curl --max-time 5 http://<public-ip>:30001  # Should timeout
```

## The Problem in 30 Seconds

**Issue:** firewalld rules can't block K3s services because kube-router's NAT rules run first.

**Example:**
```
NodePort on public IP → kube-router DNAT to pod → reaches pod ✗
(firewalld never sees it because destination changed!)
```

**Solution:** Block in `raw/PREROUTING` table **before** NAT happens.

## Usage

### 1. Apply to Existing Cluster

```bash
# Basic
ansible-playbook -i inventory.ini security-hardening.yaml

# Dry-run first (recommended)
ansible-playbook -i inventory.ini security-hardening.yaml -e "security_dry_run=true"

# Then apply
ansible-playbook -i inventory.ini security-hardening.yaml
```

### 2. Integrate with Main Playbook

Add to your playbook:

```yaml
- hosts: all
  become: true
  roles:
    - k3s_master
    - security_hardening  # Add this
```

### 3. Validate

```bash
# Automated validation
ansible-playbook -i inventory.ini security-hardening.yaml --tags validate

# Manual check
sudo iptables -t raw -L PREROUTING -n

# Test script
sudo ./scripts/test-security-hardening.sh
```

## What Gets Protected

| Port | Service | Blocked From |
|------|---------|--------------|
| 6443 | Kubernetes API | Public interface (eth0) |
| 10250 | Kubelet | Public interface (eth0) |
| 2379-2380 | etcd | Public interface (eth0) |
| 9100 | Node Exporter | Public interface (eth0) |
| 30000-32767 | NodePort range | Public interface (eth0) |

## Verify It's Working

```bash
# From external machine:

# These should TIMEOUT (blocked):
curl --max-time 5 http://<public-ip>:30001   # NodePort
curl --max-time 5 http://<public-ip>:10250   # Kubelet
curl --max-time 5 http://<public-ip>:6443    # API

# This should WORK (allowed):
curl http://<public-ip>:80                    # HTTP/ingress
curl http://<public-ip>:22                    # SSH
```

## Configuration

### Custom Interface

```bash
ansible-playbook -i inventory.ini security-hardening.yaml \
  -e "security_public_interface=ens3"
```

### Skip firewalld

```bash
ansible-playbook -i inventory.ini security-hardening.yaml \
  -e "security_configure_firewalld=false"
```

### Custom Ports

Create `group_vars/all.yaml`:

```yaml
security_blocked_ports:
  - port: "8080"
    protocol: "tcp"
    description: "Custom app"
  # ... add more
```

## Troubleshooting

### Rules Not Working

```bash
# 1. Check rules exist
sudo iptables -t raw -L PREROUTING -n

# 2. Verify interface name
ip addr show

# 3. Check rule order (must be at top)
sudo iptables -t raw -L PREROUTING -n --line-numbers

# 4. Re-run the role
ansible-playbook -i inventory.ini security-hardening.yaml
```

### Rules Lost After Reboot

```bash
# Install persistence
sudo apt-get install iptables-persistent  # Debian/Ubuntu
sudo yum install iptables-services        # RHEL/Rocky

# Or re-run with persistence
ansible-playbook -i inventory.ini security-hardening.yaml \
  -e "security_make_persistent=true"
```

## Additional Resources

- **Full Documentation:** [docs/security-hardening.md](../docs/security-hardening.md)
- **Role README:** [roles/security_hardening/README.md](../roles/security_hardening/README.md)
- **Test Script:** `scripts/test-security-hardening.sh`
- **Example Playbook:** `security-hardening.yaml`

## Quick Reference Commands

```bash
# View rules
sudo iptables -t raw -L PREROUTING -n -v

# Count blocked packets
sudo iptables -t raw -L PREROUTING -n -v | grep DROP

# Save rules
sudo iptables-save > /etc/iptables/rules.v4

# Restore rules
sudo iptables-restore < /etc/iptables/rules.v4

# Test blocked port
curl --max-time 5 http://<public-ip>:30001

# Watch traffic
sudo tcpdump -i eth0 port 30001
```

## Why raw/PREROUTING?

**iptables packet flow:**
```
1. raw/PREROUTING       ← WE BLOCK HERE ✓
2. nat/PREROUTING       ← kube-router DNAT happens here
3. filter/FORWARD       ← Too late, already DNAT'd
4. filter/INPUT         ← Never reached for NodePort
```

**Key insight:** After DNAT in step 2, destination is changed to pod IP, so filter rules matching NodePort never
trigger. We must block in step 1.

## See Also

- Connectivity Check: [docs/operational-guide.md](../docs/operational-guide.md#connectivity-check)
- Dry-Run Mode: [docs/operational-guide.md](../docs/operational-guide.md#dry-run-mode)
- Network Architecture Reference: (provided context document)
