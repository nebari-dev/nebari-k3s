# nebari-k3s

A bundle of Ansible scripts and tasks for running Nebari on K3s with enterprise-grade security.

## 🔒 Security Features

This playbook implements comprehensive security hardening for K3s clusters:

- **Dedicated firewall zone** (`k3s-cluster`) for node-to-node communication
- **Restricted NodePorts** (30000-32767) - blocked from public access by default
- **API access control** - only accessible from defined admin CIDRs
- **Blocked sensitive ports** - kubelet metrics, etcd, scheduler, controller-manager
- **SSH restrictions** - only accessible from admin CIDRs
- **Zone-based isolation** - separation between cluster, trusted, and public networks
- **Optional ingress restrictions** - control external access to services

## 📋 Quick Start

### 1. Configure Your Network

Edit `group_vars/all.yaml` with your actual network configuration:

```yaml
# Update these with YOUR network ranges
k3s_node_cidrs:
  - 10.11.0.0/24           # Your internal cluster network
  - 146.165.240.0/21       # Your external network (if needed)

# IMPORTANT: Set your admin access CIDRs
k3s_admin_cidrs:
  - 10.11.0.0/24           # Your admin network
  - YOUR_BASTION_IP/32     # Your bastion/jump host
  - YOUR_VPN_CIDR/24       # Your VPN network

# Cluster network interface
flannel_iface: eth1        # Interface for cluster communication

# Security settings
k3s_expose_ingress_publicly: true   # Set false to block external web access
k3s_expose_nodeports_publicly: false # Keep NodePorts internal
k3s_allow_nodeports_from_admin: true # Allow admin CIDR access to NodePorts
```

### 2. Run the Playbook

```bash
# Deploy the cluster
ansible-playbook -i hosts.ini playbook.yaml

# Or just update firewall rules
ansible-playbook -i hosts.ini playbook.yaml --tags common
```

### 3. Verify Security

```bash
# Check firewall zones
ansible all -i hosts.ini -m shell -a "firewall-cmd --get-active-zones"

# Verify blocked ports
ansible all -i hosts.ini -m shell -a "firewall-cmd --zone=public --list-rich-rules | grep reject"

# Test from external host (should fail)
nc -zv <node-ip> 6443   # API
nc -zv <node-ip> 10250  # kubelet
nc -zv <node-ip> 30000  # NodePort
```

## 📚 Documentation

### Core Documentation

- **[SECURITY.md](SECURITY.md)** - Complete security configuration guide
- **[MIGRATION.md](MIGRATION.md)** - Upgrade guide for existing deployments
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Command cheat sheet for operators

### Detailed Guides

- **[Configuration Variables](docs/configuration-variables.md)** - Complete variable reference with examples
- **[Storage Options](docs/storage-options.md)** - Storage backends (local-path, Longhorn, NFS, Ceph)
- **[Network Configuration](docs/network-configuration.md)** - CNI, Flannel backends, service networking
- **[Documentation Index](docs/README.md)** - Browse all documentation

## 🛡️ Security Architecture

### Firewall Zones

| Zone | Purpose | Sources | Open Ports |
|------|---------|---------|------------|
| `k3s-cluster` | Node-to-node | Node CIDRs + Individual IPs | 6443, 7946, 7472, 8472, 10250, 2379-2380 |
| `trusted` | Pod/Service traffic | 10.42.0.0/16, 10.43.0.0/16 | All |
| `public` | External access | Default interface | 22 (admin), 80/443 (optional) |

### Blocked Ports (Public Zone)

The following ports are explicitly blocked from public access:
- `6443` - K3s API (unless from admin CIDRs)
- `10250-10259` - kubelet, scheduler, controller-manager
- `2379-2380` - etcd
- `30000-32767` - NodePorts (unless from admin CIDRs)
- `6444, 8080, 8443, 9990` - Admin/debug interfaces

## ⚙️ Configuration Variables

### Quick Reference

#### Required Settings

| Variable | Description | Example |
|----------|-------------|---------|
| `k3s_node_cidrs` | Node network CIDRs | `[10.11.0.0/24]` |
| `k3s_admin_cidrs` | Admin access CIDRs | `[10.11.0.0/24, 203.0.113.50/32]` |
| `flannel_iface` | Cluster network interface | `eth1` |
| `k3s_token` | Cluster join token | `[generate secure token]` |
| `apiserver_endpoint` | API server VIP | `10.11.0.222` |

#### Security Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_expose_ingress_publicly` | `false` | Allow public web access (80/443) |
| `k3s_ingress_allowed_cidrs` | `[]` | Restrict ingress to specific CIDRs |
| `k3s_expose_nodeports_publicly` | `false` | Allow public NodePort access |
| `k3s_allow_nodeports_from_admin` | `true` | Allow admin CIDR NodePort access |
| `k3s_enable_secrets_encryption` | `true` | Encrypt secrets at rest |

#### Network & Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_flannel_backend` | `vxlan` | CNI backend (vxlan, wireguard, host-gw) |
| `k3s_enable_metallb` | `true` | Enable MetalLB LoadBalancer |
| `metal_lb_ip_range` | Required | IP range for LoadBalancer services |
| `metal_lb_mode` | `layer2` | MetalLB mode (layer2 or bgp) |

#### Components

| Variable | Default | Description |
|----------|---------|-------------|
| `k3s_enable_kubelet_metrics` | `true` | Enable kubelet metrics endpoint |
| `k3s_enable_embedded_etcd` | `true` | Use embedded etcd for HA |
| `k3s_enable_ipv6` | `false` | Enable IPv6 support |

**📖 Complete Reference**: See [Configuration Variables](docs/configuration-variables.md) for detailed documentation of all 50+ available variables

## 🚀 Deployment Scenarios

### Scenario 1: Internal Development Cluster

```yaml
k3s_node_cidrs: [10.0.0.0/8]
k3s_admin_cidrs: [10.0.0.0/8]
k3s_expose_ingress_publicly: false
k3s_expose_nodeports_publicly: false
k3s_flannel_backend: vxlan
metal_lb_ip_range: 10.11.0.191-10.11.0.199
```

### Scenario 2: Production Cluster with Bastion

```yaml
k3s_node_cidrs: [10.11.0.0/24, 146.165.240.0/21]
k3s_admin_cidrs: [10.11.0.0/24, 203.0.113.50/32]  # Bastion IP
k3s_expose_ingress_publicly: true
k3s_ingress_allowed_cidrs: []  # Public ingress
k3s_expose_nodeports_publicly: false
k3s_flannel_backend: wireguard  # Encrypted pod traffic
```

### Scenario 3: Restricted Production Cluster

```yaml
k3s_node_cidrs: [10.11.0.0/24]
k3s_admin_cidrs: [192.168.100.0/24]  # VPN network only
k3s_expose_ingress_publicly: true
k3s_ingress_allowed_cidrs: [203.0.113.0/24, 198.51.100.0/24]  # Specific CIDRs
k3s_expose_nodeports_publicly: false
```

**📖 More Examples**: See [Configuration Variables](docs/configuration-variables.md#configuration-templates) for complete templates

---

## 💾 Storage Options

This playbook uses K3s default **local-path** storage by default. For production, consider:

| Storage | Type | Replication | Use Case |
|---------|------|-------------|----------|
| **local-path** | Local | ❌ No | Development, fast local storage |
| **Longhorn** | Distributed Block | ✅ Yes | General purpose production |
| **NFS** | Network File | Depends | Shared data (RWX) |
| **Rook-Ceph** | Distributed Block/File/Object | ✅ Yes | Enterprise, all storage types |

**Storage Configuration**:

```yaml
# Default K3s local-path storage (no config needed)
# Path: /var/lib/rancher/k3s/storage/

# To change storage path, edit ConfigMap after deployment:
kubectl edit configmap -n kube-system local-path-config
```

**Deploying Alternative Storage**:

```bash
# Longhorn (replicated block storage)
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=3

# NFS (shared file storage)
helm install nfs-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=10.11.0.50 \
  --set nfs.path=/export/k8s-storage
```

**📖 Detailed Guide**: See [Storage Options](docs/storage-options.md) for complete setup instructions, migration strategies, and comparison

## 🔍 Troubleshooting

### Can't SSH to Nodes

Your IP might not be in `k3s_admin_cidrs`. Add it:

```bash
sudo firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="YOUR_IP/32" port port="22" protocol="tcp" accept'
sudo firewall-cmd --reload
```

### Nodes Can't Communicate

Node IPs must be in `k3s-cluster` zone:

```bash
sudo firewall-cmd --zone=k3s-cluster --list-sources
sudo firewall-cmd --permanent --zone=k3s-cluster --add-source=<missing-ip>/32
sudo firewall-cmd --reload
```

### API Not Accessible

Verify admin CIDR configuration:

```bash
sudo firewall-cmd --zone=public --list-rich-rules | grep 6443
```

### More Help

See [SECURITY.md](SECURITY.md) for detailed troubleshooting.

## 📊 Validation Commands

```bash
# Check firewall status
ansible all -i hosts.ini -m shell -a "firewall-cmd --state"

# List all zones
ansible all -i hosts.ini -m shell -a "firewall-cmd --list-all-zones"

# Check k3s status
ansible all -i hosts.ini -m shell -a "systemctl status k3s"

# Verify cluster health
kubectl get nodes
kubectl get pods -A
```

## 🔐 Security Best Practices

1. **Minimize admin CIDRs** - Only include trusted networks
2. **Use VPN/Bastion** - Don't expose SSH publicly
3. **Keep NodePorts internal** - Use LoadBalancer or Ingress for public services
4. **Restrict ingress** - Use `k3s_ingress_allowed_cidrs` when possible
5. **Enable audit logging** - Track API access
6. **Use Network Policies** - Add pod-level security
7. **Regular updates** - Keep K3s and OS patched
8. **Monitor logs** - Watch for unauthorized access attempts

## 📝 License

[Add your license here]

## 🤝 Contributing

[Add contribution guidelines here]

## 🧪 Security Testing

A comprehensive security test suite is provided to validate all security patches and ensure NASA compliance.

### Quick Start

```bash
cd tests/security-suite

# Test against Rocky9 vagrant lab
./quickstart.sh ../rocky9/inventories/hosts.ini

# Test against production cluster
./quickstart.sh ../../inventories/production.ini reports/prod
```

### Test Coverage

The suite includes **5 comprehensive test categories**:

1. **Port Exposure Audit** - Validates no sensitive ports are publicly accessible
   - API server (6443) blocked from unauthorized IPs
   - Kubelet (10250) not accessible externally
   - etcd (2379-2380) not accessible externally
   - NodePorts (30000-32767) properly blocked

2. **Firewall Configuration** - Validates firewalld zones and rules
   - k3s-cluster zone with DROP default
   - Public zone blocks sensitive ports
   - Admin CIDR restrictions enforced
   - Configuration persistence

3. **Network Segmentation** - Tests inter-node communication
   - Node-to-node connectivity on required ports
   - Pod network functionality
   - Service discovery (CoreDNS)
   - MetalLB and Kube-VIP operation

4. **Compliance Tests** - CIS Kubernetes Benchmark & NIST 800-53
   - CIS automated checks (if kube-bench installed)
   - NIST AC-4 (Information Flow Enforcement)
   - NIST SC-7 (Boundary Protection)
   - NIST AU-2 (Audit Logging)
   - API server security settings

5. **K3s Security** - K3s-specific validation
   - Version checks
   - Secrets encryption
   - Token file permissions
   - Container runtime security
   - Service configuration

### Reports Generated

All tests generate comprehensive reports:

- **`security-report.json`** - Machine-readable test results
- **`security-report.html`** - Interactive HTML report with charts
- **`port-scan-results.txt`** - Detailed nmap output
- **`compliance-summary.json`** - CIS/NIST compliance scoring
- **`findings.csv`** - Security findings for tracking

### Cluster Comparison

Compare security posture before and after hardening:

```bash
# Capture baseline from old cluster
./capture-baseline.sh OLD_CLUSTER_IP old-baseline.json

# Run full test suite on new cluster
./run-security-tests.sh -i ../rocky9/inventories/hosts.ini -o reports/

# Generate comparison report
./compare-clusters.sh old-baseline.json reports/security-report.json --html comparison.html
```

### NASA Compliance

The test suite validates:
- ✅ **NPR 2810.1** - Information Security Program requirements
- ✅ **NIST 800-53** - Controls AC-4, SC-7, AU-2, CM-7
- ✅ **CIS Kubernetes Benchmark** - Control plane and worker node security
- ✅ **Port Security** - No unauthenticated access to critical services

Target compliance score: **≥90%**

See [tests/security-suite/README.md](tests/security-suite/README.md) for detailed documentation.

---

## 🆘 Support

### Quick Troubleshooting

**Can't SSH to nodes?**
```bash
# Your IP not in k3s_admin_cidrs. Add temporarily:
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="YOUR_IP/32" port port="22" protocol="tcp" accept'
```

**Nodes can't communicate?**
```bash
# Check k3s-cluster zone:
sudo firewall-cmd --zone=k3s-cluster --list-sources
# Add missing node:
sudo firewall-cmd --permanent --zone=k3s-cluster --add-source=<node-ip>/32
sudo firewall-cmd --reload
```

**API not accessible?**
```bash
# Check admin CIDR configuration:
sudo firewall-cmd --zone=public --list-rich-rules | grep 6443
# Verify your IP is in k3s_admin_cidrs in group_vars/all.yaml
```

**Ingress not working?**
```bash
# Check ports 80/443:
sudo firewall-cmd --zone=public --list-ports | grep -E "80|443"
# Set k3s_expose_ingress_publicly: true in all.yaml and re-run playbook
```

### Documentation Resources

- **[Security Guide](SECURITY.md)** - Comprehensive troubleshooting section
- **[Quick Reference](QUICK-REFERENCE.md)** - Emergency procedures and fixes  
- **[Network Configuration](docs/network-configuration.md)** - Network troubleshooting
- **[Storage Options](docs/storage-options.md)** - Storage troubleshooting
- **[Migration Guide](MIGRATION.md)** - Common migration issues

### Getting Help

1. **Check logs**: 
   ```bash
   journalctl -u firewalld -n 100
   journalctl -u k3s -n 100  # or k3s-agent
   ```

2. **Validate configuration**:
   ```bash
   ./scripts/validate-security.sh <node-ip> <admin-ip>
   ```

3. **Review firewall**:
   ```bash
   firewall-cmd --list-all-zones
   iptables -L -n -v
   ```

4. **Test connectivity**:
   ```bash
   nc -zv <node-ip> <port>
   kubectl get nodes
   ```

