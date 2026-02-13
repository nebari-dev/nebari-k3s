# Security Hardening Role

## Purpose

This role implements critical security hardening for K3s clusters to prevent public internet access to sensitive
Kubernetes services. It addresses the specific issue where **kube-router's iptables NAT rules take precedence over
firewalld**, requiring raw/PREROUTING table rules to properly block traffic.

## The Problem

When K3s uses kube-router for service networking, standard firewalld rules are insufficient because:

1. **kube-router manages iptables NAT rules** in the `nat/PREROUTING` chain
2. **NAT happens before filtering** in the packet processing order
3. **NodePort traffic gets DNAT'd to pod IPs** before filter rules can block it
4. **Firewall rules in filter/INPUT are bypassed** because traffic goes to filter/FORWARD instead

### Packet Flow (Why firewalld alone fails)

```
Internet → eth0:30001 (NodePort)
    ↓
nat/PREROUTING: kube-router DNAT to 10.42.x.x:8080 (pod IP)
    ↓
Routing decision: Destination is pod IP → FORWARD
    ↓
filter/FORWARD → Pod receives traffic ✓
    ↓
filter/INPUT: NEVER REACHED (firewalld rules here don't help!)
```

### The Solution: raw/PREROUTING

Block traffic in the **raw table's PREROUTING chain** which runs **before any NAT**:

```
Internet → eth0:30001 (NodePort)
    ↓
raw/PREROUTING: DROP (our rule blocks here) ✗
    ↓
STOPPED - never reaches nat/PREROUTING or pods
```

## What This Role Does

### 1. Primary Defense: raw/PREROUTING iptables Rules

Adds rules to block sensitive ports on the public interface:

```bash
iptables -t raw -I PREROUTING 1 -i eth0 -p tcp --dport 6443 -j DROP       # API server
iptables -t raw -I PREROUTING 1 -i eth0 -p tcp --dport 10250 -j DROP      # Kubelet
iptables -t raw -I PREROUTING 1 -i eth0 -p tcp --dport 2379:2380 -j DROP  # etcd
iptables -t raw -I PREROUTING 1 -i eth0 -p tcp --dport 30000:32767 -j DROP # NodePort
```

**These rules run BEFORE kube-router's NAT rules can process the packets.**

### 2. Secondary Defense: firewalld Configuration (Defense-in-Depth)

Configures firewalld zones for additional protection:

- **Public zone (eth0)**: Default DROP, only SSH/HTTP/HTTPS allowed
- **Internal zone (eth1)**: Default ACCEPT for cluster communication

### 3. Rule Persistence

Ensures iptables rules survive reboots using:
- `netfilter-persistent` (Debian/Ubuntu)
- `iptables-services` (RHEL/Rocky/CentOS)
- Manual save to `/etc/iptables/rules.v4` (fallback)

## Usage

### Basic Usage

Add the role to your playbook:

```yaml
- hosts: k3s_cluster
  become: true
  roles:
    - role: security_hardening
```

### With Custom Configuration

```yaml
- hosts: k3s_cluster
  become: true
  roles:
    - role: security_hardening
      vars:
        security_public_interface: "ens3"  # Override auto-detection
        security_private_interface: "ens4"
        security_public_allowed_services:
          - ssh
          - http
          - https
          - custom-service
```

### Dry-Run Mode

Test without making changes:

```bash
ansible-playbook playbook.yaml --extra-vars "security_dry_run=true"
```

### Run Only Security Hardening

```bash
ansible-playbook playbook.yaml --tags security_hardening
```

### Validate Existing Rules

```bash
ansible-playbook playbook.yaml --tags validate
```

## Configuration Variables

See [defaults/main.yaml](defaults/main.yaml) for all configuration options.

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `security_public_interface` | Auto-detected (eth0) | Public-facing interface to restrict |
| `security_private_interface` | `eth1` | Internal cluster interface |
| `security_blocked_ports` | See defaults | List of ports to block from public |
| `security_configure_firewalld` | `true` | Enable firewalld configuration |
| `security_make_persistent` | `true` | Save iptables rules across reboots |
| `security_dry_run` | `false` | Preview changes without applying |

### Blocked Ports (Default)

- **6443/tcp** - Kubernetes API server
- **10250/tcp** - Kubelet API
- **2379-2380/tcp** - etcd cluster
- **9100/tcp** - Node exporter (Prometheus)
- **10255/tcp** - Kubelet read-only API
- **30000-32767/tcp,udp** - NodePort service range

## Validation

The role includes comprehensive validation:

1. **Rule installation check** - Verifies each rule in raw/PREROUTING
2. **Rule counting** - Ensures all expected rules are present
3. **Firewalld zone check** - Validates zone configuration
4. **Summary report** - Displays complete hardening status

### Manual Verification

Check raw/PREROUTING rules:
```bash
sudo iptables -t raw -L PREROUTING -n -v --line-numbers
```

Test blocked port (should timeout):
```bash
curl --max-time 5 http://<public-ip>:30001
```

Test allowed port (should work):
```bash
curl http://<public-ip>:80
```

## Integration with Existing Roles

This role works alongside other security measures:

```yaml
- hosts: k3s_cluster
  become: true
  roles:
    - connectivity_check      # Pre-flight validation
    - k3s_master             # K3s installation
    - security_hardening     # Security hardening (run AFTER K3s)
```

**Important:** Run security_hardening **after** K3s is installed so kube-router is already managing iptables.

## Troubleshooting

### Rules Not Persisting After Reboot

**Symptoms:** Security rules disappear after reboot

**Solutions:**
1. Check if persistence package is installed:
   ```bash
   # Debian/Ubuntu
   sudo apt-get install iptables-persistent netfilter-persistent

   # RHEL/Rocky/CentOS
   sudo yum install iptables-services
   sudo systemctl enable iptables
   ```

2. Manually save rules:
   ```bash
   sudo iptables-save > /etc/iptables/rules.v4
   ```

3. Re-run role with persistence enabled:
   ```bash
   ansible-playbook playbook.yaml --tags security_hardening
   ```

### Firewalld vs iptables Conflicts

**Symptoms:** Rules conflict or don't work as expected

**Solutions:**
1. Use raw/PREROUTING as primary (this role's default)
2. Disable firewalld if only using iptables:
   ```yaml
   security_configure_firewalld: false
   ```

3. Or use firewalld exclusively (if not using kube-router):
   ```yaml
   # Only configure firewalld, skip raw rules
   - include_tasks: firewalld.yaml
   ```

### kube-router Flushing Rules

**Symptoms:** Rules disappear when kube-router restarts

**Solutions:**
- raw/PREROUTING rules are **not** managed by kube-router and won't be flushed
- kube-router only manages filter/FORWARD and nat tables
- Run this role after any K3s upgrades/restarts to ensure rules are present

### Wrong Interface Detected

**Symptoms:** Rules applied to wrong interface

**Solutions:**
```yaml
# Explicitly set interfaces
security_public_interface: "ens3"
security_private_interface: "ens4"
```

## Security Considerations

### Defense-in-Depth Strategy

This role implements multiple security layers:

1. **Layer 1**: raw/PREROUTING (primary - blocks before any processing)
2. **Layer 2**: firewalld zones (secondary - defense-in-depth)
3. **Layer 3**: Service binding (configure K3s to bind to internal IP only)
4. **Layer 4**: Network policies (pod-to-pod traffic control via kube-router)

### What This Role Does NOT Do

- **Does not configure K3s service binding** (use K3s role for that)
- **Does not manage NetworkPolicies** (apply those via kubectl)
- **Does not configure egress filtering** (only ingress on public interface)
- **Does not harden SSH** (use separate SSH hardening role)

### Recommended Additional Hardening

1. **Bind K3s services to internal IP:**
   ```yaml
   # K3s server
   --bind-address=10.11.0.x
   --advertise-address=10.11.0.x
   --kubelet-arg="address=10.11.0.x"

   # K3s agent
   --node-ip=10.11.0.x
   --kubelet-arg="address=10.11.0.x"
   ```

2. **Apply NetworkPolicies:**
   ```bash
   kubectl apply -f network-policies/
   ```

3. **Enable audit logging:**
   ```yaml
   --kube-apiserver-arg="audit-log-path=/var/log/k3s-audit.log"
   ```

## References

- [K3s Security Best Practices](https://rancher.com/docs/k3s/latest/en/security/)
- [kube-router Documentation](https://www.kube-router.io/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Netfilter Packet Flow](https://en.wikipedia.org/wiki/Netfilter)
- [iptables Tables and Chains](https://www.netfilter.org/documentation/HOWTO/packet-filtering-HOWTO-6.html)

## License

Same as parent project

## Author

Nebari Development Team
