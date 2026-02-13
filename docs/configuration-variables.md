# Configuration Variables Reference

This document provides a complete reference of all configuration variables available in the K3s deployment playbook.

## Table of Contents

- [Core K3s Settings](#core-k3s-settings)
- [Network Configuration](#network-configuration)
- [Security Settings](#security-settings)
- [High Availability](#high-availability)
- [MetalLB Configuration](#metallb-configuration)
- [Kube-VIP Configuration](#kube-vip-configuration)
- [Component Toggles](#component-toggles)
- [Advanced Settings](#advanced-settings)

---

## Core K3s Settings

### `k3s_version`

**Type**: String  
**Default**: `v1.30.2+k3s2`  
**Location**: `group_vars/all.yaml`

The version of K3s to install. See [K3s releases](https://github.com/k3s-io/k3s/releases) for available versions.

**Example**:
```yaml
k3s_version: v1.30.2+k3s2
```

**Override**: Can be overridden per host or group in inventory.

---

### `k3s_token`

**Type**: String  
**Default**: `some-secret-password`  
**Required**: Yes (must be changed!)  
**Location**: `group_vars/all.yaml`

Shared secret used for nodes to join the cluster. Must be alphanumeric only.

**Security**: This is a critical security token. Use a strong random value:
```bash
# Generate secure token
openssl rand -base64 32 | tr -dc 'a-zA-Z0-9'
```

**Example**:
```yaml
k3s_token: "aB3dE5fG7hJ9kL2mN4pQ6rS8tV1wX3yZ5"
```

**Override**: Should be consistent across the cluster.

---

### `extra_server_args`

**Type**: String (multi-line)  
**Default**: See below  
**Location**: `group_vars/all.yaml`

Additional arguments passed to K3s server (master) nodes.

**Default Value**:
```yaml
extra_server_args: >-
  --tls-san {{ apiserver_endpoint }}
  --disable servicelb
  --disable traefik
  --write-kubeconfig-mode {{ k3s_write_kubeconfig_mode | default('0600') }}
  --flannel-iface={{ flannel_iface }}
```

**Common Arguments**:

| Argument | Description |
|----------|-------------|
| `--tls-san <ip/hostname>` | Add additional hostnames/IPs to API server certificate |
| `--disable servicelb` | Disable built-in ServiceLB (use MetalLB instead) |
| `--disable traefik` | Disable built-in Traefik ingress controller |
| `--write-kubeconfig-mode <mode>` | Permissions for kubeconfig file (default: 0600) |
| `--flannel-iface <interface>` | Interface for Flannel CNI |
| `--cluster-cidr <cidr>` | Network CIDR for pods (default: 10.42.0.0/16) |
| `--service-cidr <cidr>` | Network CIDR for services (default: 10.43.0.0/16) |
| `--kube-apiserver-arg <arg>` | Pass custom argument to kube-apiserver |
| `--kube-controller-manager-arg <arg>` | Pass custom argument to controller manager |
| `--kube-scheduler-arg <arg>` | Pass custom argument to scheduler |

**Example - Enable Audit Logging**:
```yaml
extra_server_args: >-
  --tls-san {{ apiserver_endpoint }}
  --disable servicelb
  --disable traefik
  --write-kubeconfig-mode 0600
  --flannel-iface={{ flannel_iface }}
  --kube-apiserver-arg=audit-log-path=/var/log/kubernetes/audit.log
  --kube-apiserver-arg=audit-policy-file=/etc/kubernetes/audit-policy.yaml
  --kube-apiserver-arg=audit-log-maxage=30
  --kube-apiserver-arg=audit-log-maxbackup=10
  --kube-apiserver-arg=audit-log-maxsize=100
```

**Override**: Can be overridden per host in `host_vars/`.

---

### `extra_agent_args`

**Type**: String (multi-line)  
**Default**: `--flannel-iface=eth1`  
**Location**: `group_vars/all.yaml`

Additional arguments passed to K3s agent (worker) nodes.

**Example**:
```yaml
extra_agent_args: >-
  --flannel-iface={{ flannel_iface }}
  --node-label="role=worker"
  --node-label="environment=production"
```

**Common Arguments**:

| Argument | Description |
|----------|-------------|
| `--flannel-iface <interface>` | Interface for Flannel CNI |
| `--node-label <key>=<value>` | Add label to node |
| `--node-taint <key>=<value>:<effect>` | Add taint to node |
| `--kubelet-arg <arg>` | Pass custom argument to kubelet |

**Override**: Can be overridden per host in `host_vars/`.

---

### `server_init_args`

**Type**: String (multi-line, templated)  
**Default**: Auto-generated based on cluster size  
**Location**: `group_vars/all.yaml`

Arguments for server initialization. Automatically configured for HA setups.

**Default Value**:
```yaml
server_init_args: >-
  {% if groups['master'] | length > 1 %}
    {% if inventory_hostname == groups['master'][0] %}
      --cluster-init
    {% else %}
      --server https://{{ master_ip | default('') }}:6443
    {% endif %}
    --token {{ k3s_token }}
  {% endif %}
  {{ extra_server_args }}
```

**Behavior**:
- Single master: No special args
- HA (first master): Adds `--cluster-init`
- HA (other masters): Adds `--server <first-master>:6443`

**Override**: Generally not needed unless custom HA setup.

---

## Network Configuration

### `flannel_iface`

**Type**: String  
**Default**: `eth1`  
**Required**: Yes  
**Location**: `group_vars/all.yaml`

Network interface used for Flannel CNI pod-to-pod communication.

**How to Determine**:
```bash
# On cluster nodes
ip -br addr show

# Look for the interface with cluster network
# Example output:
# eth0    UP  146.165.244.3/21
# eth1    UP  10.11.0.33/24     <- Use this
```

**Example**:
```yaml
flannel_iface: eth1  # or ens192, enp1s0, etc.
```

**Override**: Can be overridden per host if nodes have different interfaces.

---

### `apiserver_endpoint`

**Type**: String (IP address)  
**Required**: Yes  
**Location**: `group_vars/all.yaml`

Virtual IP (VIP) for the Kubernetes API server. Used with Kube-VIP for HA.

**Requirements**:
- Must be an unused IP in your cluster network
- Should be in same subnet as master nodes
- Not required for single-master setups (but recommended)

**Example**:
```yaml
apiserver_endpoint: 10.11.0.222
```

**Override**: Should be consistent across cluster.

---

### `k3s_node_cidrs`

**Type**: List of CIDR strings  
**Required**: Yes (for security)  
**Location**: `group_vars/all.yaml`

Network CIDRs allowed for node-to-node communication.

**Purpose**: Defines which networks can access the `k3s-cluster` firewall zone.

**Example**:
```yaml
k3s_node_cidrs:
  - 10.11.0.0/24           # Internal cluster network
  - 146.165.240.0/21       # External network (if nodes have dual NICs)
```

**Best Practice**: Include only networks where cluster nodes reside.

**Override**: Should be consistent across cluster.

---

### `k3s_flannel_backend`

**Type**: String  
**Default**: `vxlan`  
**Options**: `vxlan`, `wireguard`, `host-gw`, `ipsec`  
**Location**: `group_vars/all.yaml`

Flannel backend type for pod networking.

**Options**:

| Backend | Description | Use Case | Ports |
|---------|-------------|----------|-------|
| `vxlan` | VXLAN overlay network | Default, works everywhere | UDP 8472 |
| `wireguard` | WireGuard encrypted overlay | Security-focused | UDP 51820-51821 |
| `host-gw` | Direct routing (no overlay) | High performance, same L2 | None |
| `ipsec` | IPsec encrypted overlay | Legacy encryption | UDP 500, 4500 |

**Example**:
```yaml
k3s_flannel_backend: wireguard
```

**Override**: Should be consistent across cluster.

---

### `k3s_enable_ipv6`

**Type**: Boolean  
**Default**: `false`  
**Location**: `group_vars/all.yaml`

Enable IPv6 support for pod networking.

**Example**:
```yaml
k3s_enable_ipv6: true
```

**Note**: Requires IPv6-capable network infrastructure.

---

## Security Settings

### `k3s_admin_cidrs`

**Type**: List of CIDR strings  
**Required**: Yes (critical!)  
**Location**: `group_vars/all.yaml`

Network CIDRs allowed to access admin services (SSH, K3s API, etc.).

**Purpose**: Restricts access to sensitive services to trusted networks only.

**Example**:
```yaml
k3s_admin_cidrs:
  - 10.11.0.0/24           # Internal network
  - 192.168.100.0/24       # VPN network
  - 203.0.113.50/32        # Bastion host
  - 198.51.100.100/32      # Admin workstation
```

**Security**: Keep this list as restrictive as possible!

**Override**: Should be consistent across cluster.

---

### `k3s_expose_ingress_publicly`

**Type**: Boolean  
**Default**: `false`  
**Location**: `group_vars/all.yaml`

Whether to allow public access to ingress ports (80/443).

**Example**:
```yaml
k3s_expose_ingress_publicly: true
```

**Use Cases**:
- `true`: Public-facing web applications
- `false`: Internal-only services

---

### `k3s_ingress_allowed_cidrs`

**Type**: List of CIDR strings  
**Default**: `[]` (all sources if ingress is public)  
**Location**: `group_vars/all.yaml`

Restrict ingress access to specific CIDRs (when `k3s_expose_ingress_publicly: true`).

**Example**:
```yaml
k3s_expose_ingress_publicly: true
k3s_ingress_allowed_cidrs:
  - 203.0.113.0/24         # Corporate network
  - 198.51.100.0/24        # Partner network
```

**Note**: Empty list means all sources allowed (when ingress is public).

---

### `k3s_expose_nodeports_publicly`

**Type**: Boolean  
**Default**: `false`  
**Location**: `group_vars/all.yaml`

Whether to allow public access to NodePort range (30000-32767).

**Security**: Should remain `false` for production. Use LoadBalancer or Ingress instead.

**Example**:
```yaml
k3s_expose_nodeports_publicly: false
```

---

### `k3s_allow_nodeports_from_admin`

**Type**: Boolean  
**Default**: `true`  
**Location**: `group_vars/all.yaml`

Allow admin CIDRs to access NodePorts.

**Example**:
```yaml
k3s_allow_nodeports_from_admin: true
```

---

### `k3s_enable_secrets_encryption`

**Type**: Boolean  
**Default**: `true`  
**Location**: `group_vars/all.yaml`

Enable encryption of secrets at rest in etcd.

**Example**:
```yaml
k3s_enable_secrets_encryption: true
```

**Note**: Recommended for production environments.

---

### `k3s_write_kubeconfig_mode`

**Type**: String (octal)  
**Default**: `"0600"`  
**Location**: `group_vars/all.yaml`

File permissions for kubeconfig file.

**Options**:
- `"0600"`: Owner read/write only (most secure)
- `"0644"`: Owner read/write, others read (development)

**Example**:
```yaml
k3s_write_kubeconfig_mode: "0600"
```

---

### `k3s_allow_deprecated_schema1_images`

**Type**: Boolean  
**Default**: `false`  
**Location**: `group_vars/all.yaml`

Allow pulling deprecated Docker v1 schema images.

**Example**:
```yaml
k3s_allow_deprecated_schema1_images: false
```

**Security**: Keep disabled unless required for legacy images.

---

## High Availability

### `k3s_enable_embedded_etcd`

**Type**: Boolean  
**Default**: `true`  
**Location**: `group_vars/all.yaml`

Use embedded etcd for HA (requires 3+ master nodes).

**Example**:
```yaml
k3s_enable_embedded_etcd: true
```

**Note**: Automatically configured when multiple masters detected.

---

### `master_ip`

**Type**: String (IP address)  
**Required**: For HA setups  
**Location**: `group_vars/all.yaml`

IP address of the first master node (for other masters to join).

**Example**:
```yaml
master_ip: 10.11.0.31
```

**Override**: Not needed if using `apiserver_endpoint` with Kube-VIP.

---

## MetalLB Configuration

### `k3s_enable_metallb`

**Type**: Boolean  
**Default**: `true`  
**Location**: `group_vars/all.yaml`

Enable MetalLB for LoadBalancer service support.

**Example**:
```yaml
k3s_enable_metallb: true
```

---

### `metal_lb_type`

**Type**: String  
**Default**: `native`  
**Options**: `native`, `frr`  
**Location**: `group_vars/all.yaml`

MetalLB speaker type.

**Options**:
- `native`: Pure Go implementation (recommended)
- `frr`: Uses FRR routing daemon (advanced BGP features)

**Example**:
```yaml
metal_lb_type: native
```

---

### `metal_lb_mode`

**Type**: String  
**Default**: `layer2`  
**Options**: `layer2`, `bgp`  
**Location**: `group_vars/all.yaml`

MetalLB operating mode.

**Options**:
- `layer2`: ARP-based (simple, same L2 network)
- `bgp`: BGP routing (advanced, multi-network)

**Example**:
```yaml
metal_lb_mode: layer2
```

---

### `metal_lb_ip_range`

**Type**: String  
**Required**: Yes (if MetalLB enabled)  
**Location**: `group_vars/all.yaml`

IP address range for LoadBalancer services.

**Format**: `<start-ip>-<end-ip>` or CIDR notation

**Requirements**:
- IPs must be unused in your network
- Should be routable from clients
- Must not overlap with node IPs

**Example**:
```yaml
metal_lb_ip_range: 10.11.0.191-10.11.0.199
```

**Override**: Should be consistent across cluster.

---

### `metal_lb_speaker_tag_version`

**Type**: String  
**Default**: `v0.14.8`  
**Location**: `group_vars/all.yaml`

MetalLB speaker image version.

**Example**:
```yaml
metal_lb_speaker_tag_version: v0.14.8
```

---

### `metal_lb_controller_tag_version`

**Type**: String  
**Default**: `v0.14.8`  
**Location**: `group_vars/all.yaml`

MetalLB controller image version.

**Example**:
```yaml
metal_lb_controller_tag_version: v0.14.8
```

---

## Kube-VIP Configuration

### `kube_vip_arp`

**Type**: Boolean  
**Default**: `true`  
**Location**: `group_vars/all.yaml`

Enable ARP for Kube-VIP virtual IP.

**Example**:
```yaml
kube_vip_arp: true
```

**Note**: Required for layer 2 VIP operation.

---

### `kube_vip_tag_version`

**Type**: String  
**Default**: `v0.8.2`  
**Location**: `group_vars/all.yaml`

Kube-VIP image version.

**Example**:
```yaml
kube_vip_tag_version: v0.8.2
```

---

## Component Toggles

### `k3s_enable_kubelet_metrics`

**Type**: Boolean  
**Default**: `true`  
**Location**: `group_vars/all.yaml`

Enable kubelet metrics endpoint (port 10250).

**Example**:
```yaml
k3s_enable_kubelet_metrics: true
```

**Note**: Required for monitoring solutions like Prometheus.

---

## Advanced Settings

### `ansible_user`

**Type**: String  
**Default**: `vagrant`  
**Location**: `group_vars/all.yaml` or inventory

User for Ansible SSH connections.

**Example**:
```yaml
ansible_user: sumphlet
```

**Override**: Can be set per host in inventory.

---

## Variable Override Hierarchy

Variables can be set at multiple levels (from lowest to highest precedence):

1. **Role defaults**: `roles/*/defaults/main.yaml`
2. **Group vars**: `group_vars/all.yaml`
3. **Host vars**: `host_vars/<hostname>.yaml`
4. **Playbook vars**: `playbook.yaml`
5. **Extra vars**: `-e "var=value"` (command line)

### Example Override Structure

```bash
nebari-k3s/
├── group_vars/
│   ├── all.yaml              # Cluster-wide defaults
│   ├── master.yaml           # Master-specific
│   └── worker.yaml           # Worker-specific
├── host_vars/
│   ├── node-01.yaml          # Host-specific
│   └── node-02.yaml
```

**Example - Different Interface Per Host**:

`host_vars/node-special.yaml`:
```yaml
flannel_iface: ens192  # Different interface for this host
extra_agent_args: >-
  --flannel-iface=ens192
  --node-label="special=true"
```

---

## Configuration Templates

### Minimal Configuration

```yaml
k3s_version: v1.30.2+k3s2
k3s_token: "CHANGE_ME"
flannel_iface: eth1
apiserver_endpoint: 10.11.0.222

k3s_node_cidrs:
  - 10.11.0.0/24

k3s_admin_cidrs:
  - 10.11.0.0/24

k3s_enable_metallb: true
metal_lb_ip_range: 10.11.0.191-10.11.0.199
```

### Production Configuration

```yaml
k3s_version: v1.30.2+k3s2
k3s_token: "aB3dE5fG7hJ9kL2mN4pQ6rS8tV1wX3yZ5"
flannel_iface: eth1
apiserver_endpoint: 10.11.0.222

extra_server_args: >-
  --tls-san {{ apiserver_endpoint }}
  --disable servicelb
  --disable traefik
  --write-kubeconfig-mode 0600
  --flannel-iface={{ flannel_iface }}
  --kube-apiserver-arg=audit-log-path=/var/log/kubernetes/audit.log
  --kube-apiserver-arg=audit-policy-file=/etc/kubernetes/audit-policy.yaml

k3s_node_cidrs:
  - 10.11.0.0/24
  - 146.165.240.0/21

k3s_admin_cidrs:
  - 10.11.0.0/24
  - 203.0.113.50/32

k3s_expose_ingress_publicly: true
k3s_ingress_allowed_cidrs: []
k3s_expose_nodeports_publicly: false
k3s_allow_nodeports_from_admin: true

k3s_flannel_backend: wireguard
k3s_enable_ipv6: false
k3s_enable_metallb: true
k3s_enable_kubelet_metrics: true
k3s_enable_embedded_etcd: true

metal_lb_type: native
metal_lb_mode: layer2
metal_lb_ip_range: 10.11.0.191-10.11.0.199

k3s_write_kubeconfig_mode: "0600"
k3s_enable_secrets_encryption: true
k3s_allow_deprecated_schema1_images: false
```

---

## See Also

- [Storage Options](storage-options.md)
- [Security Configuration](../SECURITY.md)
- [Network Configuration](network-configuration.md)
