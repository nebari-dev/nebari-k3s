# Inventory

This directory contains all inventory files and variables for managing nebari-k3s clusters across different
environments.

## Structure

```
inventory/
├── production.ini          # Production inventory
├── staging.ini.example     # Example staging inventory
├── group_vars/             # Variables for groups of hosts
│   ├── all.yaml           # Variables for all hosts
│   └── k3s_master.yaml    # (optional) Master-specific vars
├── host_vars/              # Variables for specific hosts
│   └── node1.yaml         # (optional) Per-host vars
└── examples/               # Example inventory configurations
```

## Quick Start

### 1. Create Your Inventory

Copy the example and customize:

```bash
# For production
cp examples/production.ini.example production.ini
vi production.ini

# For staging/development
cp examples/staging.ini.example staging.ini
vi staging.ini
```

### 2. Configure Variables

Edit `group_vars/all.yaml`:

```yaml
# Network configuration
k3s_node_cidrs:
  - 10.11.0.0/24           # Your internal cluster network

k3s_admin_cidrs:
  - 10.11.0.0/24           # Your admin network
  - YOUR_VPN_CIDR/24       # Your VPN network

# Cluster interface
flannel_iface: eth1

# Security settings
k3s_expose_ingress_publicly: true
k3s_expose_nodeports_publicly: false
```

### 3. Test Connectivity

```bash
# Verify inventory and connectivity
ansible-playbook -i production.ini ../playbooks/connectivity-check.yaml
```

## Inventory File Format

### [production.ini](production.ini)

```ini
# K3s Master Nodes (Control Plane)
[k3s_master]
master1 ansible_host=10.11.0.10 ansible_user=ubuntu
master2 ansible_host=10.11.0.11 ansible_user=ubuntu
master3 ansible_host=10.11.0.12 ansible_user=ubuntu

# K3s Worker Nodes (Agent)
[k3s_worker]
worker1 ansible_host=10.11.0.20 ansible_user=ubuntu
worker2 ansible_host=10.11.0.21 ansible_user=ubuntu
worker3 ansible_host=10.11.0.22 ansible_user=ubuntu

# All K3s nodes
[k3s_cluster:children]
k3s_master
k3s_worker

# Cluster-wide variables
[k3s_cluster:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become=true
ansible_become_method=sudo
```

### Host Variables

Per-host configuration in `host_vars/`, e.g., `host_vars/master1.yaml`:

```yaml
---
# Override for this specific host
ansible_host: 10.11.0.10
ansible_user: ubuntu
ansible_port: 22

# Host-specific K3s settings
k3s_server_args:
  - "--disable=servicelb"  # Disable if using external LB
```

### Group Variables

Shared configuration in `group_vars/`, e.g., `group_vars/k3s_master.yaml`:

```yaml
---
# Variables for all master nodes
k3s_server_init: true

k3s_server_args:
  - "--cluster-init"
  - "--disable=traefik"
```

## Variable Precedence

Ansible loads variables in this order (lowest to highest precedence):

1. `group_vars/all.yaml` - All hosts
2. `group_vars/k3s_cluster.yaml` - All cluster nodes
3. `group_vars/k3s_master.yaml` - All master nodes
4. `host_vars/master1.yaml` - Specific host
5. Inventory file `[group:vars]`
6. Playbook vars
7. Extra vars (`-e` flag)

## Common Scenarios

### Multi-Environment Setup

```bash
inventory/
├── production.ini
├── staging.ini
├── development.ini
├── group_vars/
│   ├── all.yaml                    # Shared defaults
│   ├── production/
│   │   └── all.yaml               # Production-specific
│   ├── staging/
│   │   └── all.yaml               # Staging-specific
│   └── development/
│       └── all.yaml               # Dev-specific
```

Use with:
```bash
ansible-playbook -i inventory/production.ini playbooks/site.yaml
ansible-playbook -i inventory/staging.ini playbooks/site.yaml
```

### Dynamic Inventory

For cloud environments (AWS, GCP, Azure):

```bash
# Use dynamic inventory script
ansible-playbook -i inventory/aws_ec2.yaml playbooks/site.yaml

# Or combine static + dynamic
ansible-playbook -i inventory/production.ini \
  -i inventory/aws_ec2.yaml \
  playbooks/site.yaml
```

### Testing with Local VMs

```bash
# Use Vagrant test inventory
ansible-playbook -i ../tests/integration/vagrant/hosts.ini playbooks/site.yaml
```

## Essential Variables

### Network Configuration

```yaml
# Cluster networking
k3s_node_cidrs:
  - 10.11.0.0/24          # Private cluster network
  - 172.16.0.0/16         # Additional network

flannel_iface: eth1       # Interface for cluster communication

# Admin access
k3s_admin_cidrs:
  - 10.11.0.0/24          # Admin network
  - 192.168.1.100/32      # Specific admin IP
```

### Security Settings

```yaml
# Public access control
k3s_expose_ingress_publicly: true    # Allow HTTP/HTTPS ingress
k3s_expose_nodeports_publicly: false # Block NodePort from internet
k3s_allow_nodeports_from_admin: true # Allow NodePort from admin CIDRs

# Interface configuration
security_public_interface: eth0       # Public-facing interface
security_private_interface: eth1      # Internal cluster interface
```

### K3s Configuration

```yaml
# K3s version
k3s_version: v1.28.5+k3s1

# Server arguments (control plane)
k3s_server_args:
  - "--disable=traefik"
  - "--disable=servicelb"
  - "--write-kubeconfig-mode=644"

# Agent arguments (worker nodes)
k3s_agent_args:
  - "--node-label=node.kubernetes.io/instance-type=worker"
```

## Validation

### Verify Inventory

```bash
# List all hosts
ansible-inventory -i production.ini --list

# Show host details
ansible-inventory -i production.ini --host master1

# Graph inventory
ansible-inventory -i production.ini --graph
```

### Test Variables

```bash
# Show all variables for a host
ansible -i production.ini master1 -m debug -a "var=hostvars[inventory_hostname]"

# Check specific variable
ansible -i production.ini all -m debug -a "var=k3s_node_cidrs"
```

### Connectivity Test

```bash
# Ping all hosts
ansible -i production.ini all -m ping

# Test sudo
ansible -i production.ini all -b -m command -a "whoami"

# Check Python
ansible -i production.ini all -m command -a "python3 --version"
```

## Troubleshooting

### Connection Issues

```bash
# Verbose output
ansible -i production.ini all -m ping -vvv

# Test specific host
ansible -i production.ini master1 -m ping -vvv

# Check SSH manually
ssh -i ~/.ssh/id_rsa ubuntu@10.11.0.10
```

### Variable Problems

```bash
# Dump all variables
ansible-playbook -i production.ini playbooks/site.yaml \
  -e "dump_vars=true" --tags never

# Check variable precedence
ansible -i production.ini master1 -m debug \
  -a "var=k3s_server_args"
```

### Permission Issues

```bash
# Test sudo access
ansible -i production.ini all -b -m command -a "whoami"

# Check sudoers configuration
ansible -i production.ini all -b -m shell \
  -a "grep ubuntu /etc/sudoers.d/*"
```

## Security Best Practices

1. **Never commit secrets** - Use Ansible Vault or external secret management
2. **Use SSH keys** - Avoid password authentication
3. **Limit sudo access** - Use `become_user` when needed
4. **Encrypt sensitive vars** - Use `ansible-vault encrypt`
5. **Restrict file permissions** - `chmod 600` for SSH keys
6. **Use bastion hosts** - Jump through bastion for production

### Using Ansible Vault

```bash
# Encrypt sensitive file
ansible-vault encrypt group_vars/production/secrets.yaml

# Edit encrypted file
ansible-vault edit group_vars/production/secrets.yaml

# Run playbook with vault
ansible-playbook -i production.ini playbooks/site.yaml --ask-vault-pass

# Or use password file
ansible-playbook -i production.ini playbooks/site.yaml \
  --vault-password-file ~/.vault_pass
```

## See Also

- [../playbooks/](../playbooks/) - Available playbooks
- [group_vars/all.yaml](group_vars/all.yaml) - Default variables
- [examples/](examples/) - Example configurations
- [../docs/configuration-variables.md](../docs/configuration-variables.md) - Complete variable reference
