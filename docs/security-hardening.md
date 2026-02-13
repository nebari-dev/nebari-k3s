# Security Hardening Guide

## Overview

This guide explains the security hardening implementation for nebari-k3s clusters, specifically addressing the challenge
of blocking public interface access when using kube-router.

## The Challenge: Why firewalld Isn't Enough

When deploying K3s with kube-router (the default networking component), a **critical security issue** emerges:

### The Problem

**Symptom:** Even with firewalld rules blocking ports, services like NodePort remain accessible from the public
internet.

**Root Cause:** kube-router manages iptables NAT rules that **run before firewalld's filter rules**, causing the
filtering to be bypassed.

### Packet Flow Diagram

**What happens with firewalld only:**

```
Internet → eth0:30001 (NodePort service)
    │
    ↓ 1. raw table (empty - no rules)
    ↓ 2. mangle table (packet modifications)
    ↓ 3. nat/PREROUTING (kube-router DNAT: 146.165.x.x:30001 → 10.42.x.x:8080)
    │
    ↓ 4. Routing decision
    │    Destination is now 10.42.x.x (pod IP) → FORWARD chain
    │
    ↓ 5. filter/FORWARD (NetworkPolicy rules)
    │    ↓ Pod receives traffic ✓
    │
    └─► filter/INPUT (firewalld rules)
         NEVER REACHED! ✗
```

**Result:** External traffic reaches internal pods, bypassing firewall rules.

### The Solution: raw/PREROUTING

Block traffic **before any NAT processing** in the raw table:

```
Internet → eth0:30001 (NodePort service)
    │
    ↓ 1. raw/PREROUTING
    │    Rule: DROP if interface=eth0 AND port=30001
    │    ✓ BLOCKED HERE
    │
    X Never reaches nat/PREROUTING
    X Never reaches filter chains
    X Never reaches pods
```

**Result:** Traffic blocked at the earliest possible point, before kube-router can process it.

## Implementation

### Automated Deployment

Use the `security_hardening` Ansible role:

```bash
# Apply security hardening to existing cluster
ansible-playbook -i inventory.ini security-hardening.yaml

# Dry-run mode (preview changes)
ansible-playbook -i inventory.ini security-hardening.yaml -e "security_dry_run=true"

# Custom interface
ansible-playbook -i inventory.ini security-hardening.yaml -e "security_public_interface=ens3"
```

### What Gets Protected

By default, the following ports are blocked on the public interface:

| Port | Service | Why It's Critical |
|------|---------|-------------------|
| **6443** | Kubernetes API | Direct cluster control - compromise = full cluster access |
| **10250** | Kubelet API | Execute commands in pods, read secrets |
| **2379-2380** | etcd | Cluster state database - contains all secrets |
| **9100** | Node Exporter | System metrics - information disclosure |
| **30000-32767** | NodePort range | Direct pod access - bypasses ingress controls |

### Defense-in-Depth Layers

The security hardening implements **multiple protection layers**:

```
┌─────────────────────────────────────────────┐
│  Layer 1: raw/PREROUTING iptables          │  ← Primary defense
│  - Blocks BEFORE any NAT processing        │
│  - Immune to kube-router changes           │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  Layer 2: firewalld zones                  │  ← Secondary defense
│  - Public zone: DROP by default            │
│  - Internal zone: ACCEPT cluster traffic   │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  Layer 3: K3s service binding               │  ← Configuration hardening
│  - Services bind to internal IP only       │
│  - --node-ip, --bind-address, etc.         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  Layer 4: NetworkPolicies                   │  ← Application-level
│  - Pod-to-pod microsegmentation            │
│  - Managed by kube-router                  │
└─────────────────────────────────────────────┘
```

## Configuration

### Basic Configuration

The role uses sensible defaults but can be customized:

```yaml
# In your playbook or group_vars
security_public_interface: "eth0"      # Auto-detected by default
security_private_interface: "eth1"     # Internal cluster interface

security_configure_firewalld: true     # Enable firewalld layer
security_make_persistent: true         # Survive reboots

security_public_allowed_services:
  - ssh
  - http
  - https
```

### Custom Port Blocking

Add additional ports to block:

```yaml
security_blocked_ports:
  # Default ports (API, kubelet, etcd, metrics, NodePort)
  - port: "6443"
    protocol: "tcp"
    description: "Kubernetes API server"

  # Add custom ports
  - port: "8080"
    protocol: "tcp"
    description: "Custom application"
  - port: "5432"
    protocol: "tcp"
    description: "PostgreSQL"
```

### Interface Detection

The role auto-detects interfaces, but you can override:

```yaml
# Automatic (uses ansible_default_ipv4.interface)
security_public_interface: "{{ ansible_default_ipv4.interface }}"

# Explicit
security_public_interface: "ens3"
security_private_interface: "ens4"
```

## Validation

### Automated Validation

The role includes built-in validation:

```bash
# Run validation checks
ansible-playbook -i inventory.ini security-hardening.yaml --tags validate
```

### Manual Validation

**1. Check raw/PREROUTING rules:**

```bash
sudo iptables -t raw -L PREROUTING -n -v --line-numbers
```

Expected output:
```
Chain PREROUTING (policy ACCEPT)
num   pkts bytes target     prot opt in     out     source               destination
1        0     0 DROP       tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpts:30000:32767 /* nebari-k3s: Block NodePort service range */
2        0     0 DROP       tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:10250 /* nebari-k3s: Block Kubelet API */
3        0     0 DROP       tcp  --  eth0   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:6443 /* nebari-k3s: Block Kubernetes API server */
```

**2. Test blocked port (should timeout):**

```bash
# From external machine
curl --max-time 5 http://<public-ip>:30001
# Expected: timeout

curl --max-time 5 -k https://<public-ip>:10250
# Expected: timeout
```

**3. Test allowed port (should work):**

```bash
curl http://<public-ip>:80
# Expected: Response from ingress controller
```

### Automated Test Script

Use the provided test script:

```bash
# On the cluster node
sudo /path/to/scripts/test-security-hardening.sh
```

Output:
```
═══════════════════════════════════════════════════════
Security Hardening Validation Script
═══════════════════════════════════════════════════════

[Test 1/5] Checking raw/PREROUTING rules...
✓ PASS - raw/PREROUTING rules found
  Found 7 DROP rules for eth0

[Test 2/5] Checking NodePort range (30000-32767) blocking...
✓ PASS - NodePort range is blocked

[Test 3/5] Checking Kubelet port (10250) blocking...
✓ PASS - Kubelet port is blocked

[Test 4/5] Checking API Server port (6443) blocking...
✓ PASS - API Server port is blocked

[Test 5/5] Checking rule persistence configuration...
✓ PASS - Rules persistence configured
```

## Persistence

### How Rules are Saved

The role automatically configures persistence based on your OS:

**Debian/Ubuntu:**
```bash
# Uses netfilter-persistent
sudo apt-get install iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

**RHEL/Rocky/CentOS:**
```bash
# Uses iptables-services
sudo yum install iptables-services
sudo systemctl enable iptables
sudo iptables-save > /etc/sysconfig/iptables
```

**Fallback:**
```bash
# Manual save
sudo iptables-save > /etc/iptables/rules.v4
```

### Verifying Persistence

**Check if persistence is configured:**
```bash
# Debian/Ubuntu
dpkg -l | grep netfilter-persistent

# RHEL/Rocky/CentOS
systemctl status iptables

# Manual
ls -la /etc/iptables/rules.v4
```

**Test persistence:**
```bash
# 1. Check current rules
sudo iptables -t raw -L PREROUTING -n | grep DROP

# 2. Reboot
sudo reboot

# 3. After reboot, check again
sudo iptables -t raw -L PREROUTING -n | grep DROP
# Should show same rules
```

## Troubleshooting

### Rules Not Blocking Traffic

**Symptoms:** Services still accessible from public IP

**Diagnosis:**
```bash
# 1. Check if rules exist
sudo iptables -t raw -L PREROUTING -n

# 2. Check rule order (MUST be at top)
sudo iptables -t raw -L PREROUTING -n --line-numbers

# 3. Verify interface name
ip addr show

# 4. Test with tcpdump
sudo tcpdump -i eth0 port 30001
```

**Solutions:**
1. Ensure rules are in positions 1-N (top of chain)
2. Verify correct interface name
3. Re-run the security hardening role
4. Check for conflicting rules flushing the table

### Rules Disappear After Reboot

**Symptoms:** Rules present after apply, but gone after reboot

**Solutions:**

1. **Install persistence package:**
   ```bash
   # Debian/Ubuntu
   sudo apt-get install iptables-persistent netfilter-persistent

   # RHEL/Rocky/CentOS
   sudo yum install iptables-services
   sudo systemctl enable iptables
   ```

2. **Manually save rules:**
   ```bash
   sudo iptables-save > /etc/iptables/rules.v4
   ```

3. **Create systemd service:**
   ```bash
   # /etc/systemd/system/iptables-restore.service
   [Unit]
   Description=Restore iptables rules
   Before=network-pre.target
   Wants=network-pre.target

   [Service]
   Type=oneshot
   ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4

   [Install]
   WantedBy=multi-user.target
   ```

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable iptables-restore
   ```

4. **Re-run role with persistence:**
   ```bash
   ansible-playbook -i inventory.ini security-hardening.yaml \
     -e "security_make_persistent=true"
   ```

### kube-router Conflicts

**Symptoms:** Rules work initially but disappear when kube-router restarts

**Explanation:** kube-router **does not manage raw table**, only filter/FORWARD and nat tables. Raw rules should
persist.

**Verification:**
```bash
# Before kube-router restart
sudo iptables -t raw -L PREROUTING -n | wc -l

# Restart kube-router
kubectl delete pod -n kube-system -l k8s-app=kube-router

# After kube-router restart (should be same)
sudo iptables -t raw -L PREROUTING -n | wc -l
```

If rules disappear, something else is flushing iptables:
```bash
# Check systemd services that might flush rules
systemctl list-units | grep -E 'iptables|firewall'

# Check cron jobs
crontab -l
sudo crontab -l
```

### Firewalld vs iptables Conflicts

**Symptoms:** Rules conflict, unexpected behavior

**Understanding the relationship:**

- **firewalld** uses iptables underneath
- **raw table** rules run before firewalld
- Both can coexist safely
- raw table is NOT managed by firewalld

**Solutions:**

1. **Use both (recommended):**
   ```yaml
   security_configure_firewalld: true  # Defense-in-depth
   ```

2. **Use only raw/PREROUTING:**
   ```yaml
   security_configure_firewalld: false
   ```

3. **Disable firewalld completely:**
   ```bash
   sudo systemctl stop firewalld
   sudo systemctl disable firewalld
   ```

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Apply security hardening
  run: |
    cd /path/to/nebari-k3s
    ansible-playbook -i tests/vagrant/hosts.ini security-hardening.yaml

- name: Validate security hardening
  run: |
    ansible-playbook -i tests/vagrant/hosts.ini security-hardening.yaml --tags validate

- name: Test blocked ports
  run: |
    # Should timeout
    ! timeout 5 curl http://192.168.56.11:30001

    # Should work
    curl http://192.168.56.11:80
```

### Pre-flight Checks

Combine with connectivity check:

```yaml
- hosts: all
  become: true
  roles:
    - connectivity_check     # Pre-flight validation
    - k3s_master            # K3s installation
    - security_hardening    # Security hardening
```

## Security Best Practices

### Recommended Configuration

1. **Always use raw/PREROUTING** (primary defense)
2. **Enable firewalld** (defense-in-depth)
3. **Bind K3s services to internal IP** (configuration hardening)
4. **Apply NetworkPolicies** (application-level segmentation)
5. **Monitor and audit** (detect violations)

### Additional Hardening

**1. Bind K3s to internal interface:**

```yaml
# roles/k3s_master/defaults/main.yaml
k3s_server_args:
  - "--bind-address={{ ansible_eth1.ipv4.address }}"
  - "--advertise-address={{ ansible_eth1.ipv4.address }}"
  - "--node-ip={{ ansible_eth1.ipv4.address }}"
  - "--kubelet-arg=address={{ ansible_eth1.ipv4.address }}"
```

**2. Apply default-deny NetworkPolicies:**

```yaml
# network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**3. Enable audit logging:**

```yaml
k3s_server_args:
  - "--kube-apiserver-arg=audit-log-path=/var/log/k3s-audit.log"
  - "--kube-apiserver-arg=audit-log-maxage=30"
```

**4. Restrict SSH access:**

```yaml
# In firewalld public zone
security_public_allowed_services:
  - ssh  # Consider restricting to specific IPs
```

Or use rich rules:
```bash
firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="1.2.3.4/32" service name="ssh" accept'
```

## Monitoring and Auditing

### Monitor Blocked Traffic

```bash
# Watch blocked packets in real-time
sudo watch -n1 'iptables -t raw -L PREROUTING -n -v | head -15'

# Log dropped packets (add to rules)
iptables -t raw -I PREROUTING 1 -i eth0 -p tcp --dport 30000:32767 -j LOG --log-prefix "BLOCKED-NODEPORT: "
```

### Audit Logs

```bash
# View blocked traffic
sudo journalctl -k | grep BLOCKED-NODEPORT

# View firewalld denials
sudo journalctl -u firewalld | grep -i deny
```

### Metrics and Alerting

Consider adding Prometheus metrics:

```yaml
# prometheus-rules.yaml
groups:
- name: security
  rules:
  - alert: UnauthorizedAccessAttempt
    expr: rate(iptables_blocked_packets_total[5m]) > 10
    annotations:
      summary: "High rate of blocked traffic on {{ $labels.instance }}"
```

## References

- [K3s Security Hardening](https://docs.k3s.io/security/hardening-guide)
- [kube-router Documentation](https://www.kube-router.io/)
- [Netfilter Packet Flow](https://en.wikipedia.org/wiki/Netfilter)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [iptables Tutorial](https://www.netfilter.org/documentation/HOWTO/packet-filtering-HOWTO.html)

## Support

For issues or questions:
1. Check [roles/security_hardening/README.md](../roles/security_hardening/README.md)
2. Review [Troubleshooting](#troubleshooting) section
3. Open an issue on GitHub with:
   - Output of `iptables -t raw -L PREROUTING -n -v`
   - Output of `ip addr show`
   - Ansible playbook run with `-vvv`
