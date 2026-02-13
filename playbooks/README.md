# Playbooks

This directory contains all Ansible playbooks for managing the nebari-k3s cluster.

## Available Playbooks

### [site.yaml](site.yaml)
**Main deployment playbook** - Deploys and configures the complete K3s cluster with security hardening.

**Usage:**
```bash
# Full deployment
ansible-playbook -i ../inventory/production.ini site.yaml

# Dry-run mode (preview changes)
../scripts/dry-run.sh -i ../inventory/production.ini

# Update specific components
ansible-playbook -i ../inventory/production.ini site.yaml --tags common
ansible-playbook -i ../inventory/production.ini site.yaml --tags k3s
```

**What it does:**
- Installs and configures K3s (server and agent nodes)
- Configures firewalld security zones
- Sets up cluster networking (Flannel)
- Applies security hardening
- Configures kubeconfig access



### [connectivity-check.yaml](connectivity-check.yaml)
**Pre-flight validation** - Verifies SSH access and basic commands on all nodes before deployment.

**Usage:**
```bash
# Check all nodes
ansible-playbook -i ../inventory/production.ini connectivity-check.yaml

# Verbose output
ansible-playbook -i ../inventory/production.ini connectivity-check.yaml \
  -e connectivity_check_verbose=true

# Check specific node
ansible-playbook -i ../inventory/production.ini connectivity-check.yaml \
  -l problem-node
```

**Checks:**
- ✓ SSH connectivity to all nodes
- ✓ Sudo access (become: true)
- ✓ Python availability
- ✓ Basic command execution
- ✓ Ansible facts gathering

**When to use:**
- Before first deployment
- After infrastructure changes
- Debugging connection issues
- Validating new node additions



### [security-hardening.yaml](security-hardening.yaml)
**Security hardening** - Applies advanced security rules including raw/PREROUTING iptables.

**Usage:**
```bash
# Apply security hardening
ansible-playbook -i ../inventory/production.ini security-hardening.yaml

# Dry-run mode (preview changes)
ansible-playbook -i ../inventory/production.ini security-hardening.yaml \
  -e security_dry_run=true

# Validation only
ansible-playbook -i ../inventory/production.ini security-hardening.yaml \
  --tags validate
```

**What it does:**
- Adds raw/PREROUTING iptables rules (blocks before kube-router NAT)
- Configures firewalld zones (defense-in-depth)
- Blocks NodePort range from public interface
- Blocks management ports (kubelet, API, etcd, metrics)
- Ensures rules persist across reboots

**Why separate from site.yaml:**
- Can be applied to existing clusters
- Addresses kube-router NAT precedence issue
- Idempotent - safe to re-run
- Includes comprehensive validation

**Documentation:**
- Role: `../roles/security_hardening/README.md`
- Guide: `../docs/security-hardening.md`
- Quick Start: `../roles/security_hardening/QUICKSTART.md`



## Playbook Development

### Creating a New Playbook

```yaml
---
# playbooks/my-playbook.yaml
- name: Description of what this playbook does
  hosts: all  # or specific group
  become: true
  gather_facts: true

  vars:
    # Playbook-specific variables

  pre_tasks:
    - name: Pre-flight checks
      # ...

  roles:
    - role: my_role
      tags:
        - my_role

  post_tasks:
    - name: Validation
      # ...
```

### Best Practices

1. **Always include pre-flight checks** - Use connectivity-check patterns
2. **Support dry-run mode** - Add `-e dry_run=true` support
3. **Use tags extensively** - Allow selective execution
4. **Document what changed** - Clear task names and debug output
5. **Make it idempotent** - Safe to run multiple times
6. **Include validation** - Verify changes were applied correctly

### Testing Playbooks

```bash
# 1. Syntax check
ansible-playbook playbooks/my-playbook.yaml --syntax-check

# 2. Dry-run (check mode)
ansible-playbook -i inventory/production.ini playbooks/my-playbook.yaml --check

# 3. Run against test environment
ansible-playbook -i tests/integration/vagrant/hosts.ini playbooks/my-playbook.yaml

# 4. Validate the result
ansible-playbook -i inventory/production.ini playbooks/my-playbook.yaml --tags validate
```

## See Also

- [../inventory/](../inventory/) - Inventory and variable configuration
- [../roles/](../roles/) - Ansible roles
- [../docs/operational-guide.md](../docs/operational-guide.md) - Operational procedures
- [../tests/integration/](../tests/integration/) - Integration testing
