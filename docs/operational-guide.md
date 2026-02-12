# Operational Guide: Dry-Run, Connectivity Check & Idempotency

This guide covers three important operational improvements for managing your k3s clusters safely and efficiently.

---

## 1. 🔍 Dry-Run Mode (Plan/Diff)

The dry-run script shows exactly what would change **without** making any modifications to your systems.

### Usage

```bash
# Basic dry-run against vagrant lab
./scripts/dry-run.sh -i tests/rocky9/inventories/hosts.ini

# Dry-run on production with verbose output
./scripts/dry-run.sh -i inventory/production.ini -v

# Check only firewall changes on master nodes
./scripts/dry-run.sh -i inventory/staging.ini -l master -t firewall

# Save output to file for review
./scripts/dry-run.sh -i inventory/production.ini -o /tmp/production-plan.log
```

### Options

| Option | Description |
|--------|-------------|
| `-i, --inventory` | Inventory file (required) |
| `-l, --limit` | Limit to specific hosts/groups |
| `-t, --tags` | Run only specific tags |
| `-s, --skip-tags` | Skip specific tags |
| `-v, --verbose` | Verbose output (-vv, -vvv for more) |
| `-o, --output` | Save output to file |
| `-h, --help` | Show help message |

### What it shows

- ✅ File diffs for configuration changes
- ✅ Packages to install/remove
- ✅ Service state changes
- ✅ Template modifications
- ✅ Firewall rule changes
- ✅ Exit code: 0 = no changes, 2 = changes detected

### Best Practices

1. **Always dry-run on production first**
   ```bash
   ./scripts/dry-run.sh -i inventory/production.ini -o /tmp/prod-$(date +%Y%m%d).log
   ```

2. **Review the output carefully** before applying
   
3. **Use for change review in PRs**
   ```bash
   ./scripts/dry-run.sh -i tests/rocky9/inventories/hosts.ini > ci-dry-run.log
   ```

4. **Document expected changes** in your deployment plan

---

## 2. 🔌 Connectivity Check

Quick validation that all nodes are accessible and basic sysadmin commands work properly.

### Usage

```bash
# Check all nodes
ansible-playbook -i inventory/hosts.ini connectivity-check.yaml

# Check only master nodes
ansible-playbook -i inventory/hosts.ini connectivity-check.yaml -l master

# Verbose output with detailed command results
ansible-playbook -i inventory/hosts.ini connectivity-check.yaml -e connectivity_check_verbose=true

# Check vagrant lab
ansible-playbook -i tests/rocky9/inventories/hosts.ini connectivity-check.yaml
```

### What it validates

- ✅ SSH connectivity to all nodes
- ✅ Sudo/privilege escalation
- ✅ Python availability (required for Ansible)
- ✅ Basic system commands (hostname, uptime, df, free, ip)
- ✅ DNS resolution
- ✅ Network connectivity between cluster nodes
- ✅ Critical service status (sshd, firewalld)

### When to use

1. **Before running the main playbook** (especially on new infrastructure)
   ```bash
   ansible-playbook -i inventory/hosts.ini connectivity-check.yaml
   ```

2. **After infrastructure changes** (network, firewall, etc.)

3. **Troubleshooting connection issues**
   ```bash
   ansible-playbook -i inventory/hosts.ini connectivity-check.yaml -l problematic-node -e connectivity_check_verbose=true
   ```

4. **In CI/CD pipelines** before deployment

### Example workflow

```bash
# 1. First check connectivity
ansible-playbook -i inventory/production.ini connectivity-check.yaml

# 2. Then do a dry-run
./scripts/dry-run.sh -i inventory/production.ini

# 3. Finally apply changes
ansible-playbook -i inventory/production.ini playbook.yaml
```

---

## 3. 🔄 Idempotent K3s Installation

The k3s installation is now fully idempotent - you can run the playbook multiple times safely without breaking anything.

### What changed

#### Master Nodes (`roles/k3s_master`)
- ✅ Checks if k3s is already installed
- ✅ Verifies current version before upgrading
- ✅ Checks service state (active/inactive)
- ✅ Only installs/upgrades when needed
- ✅ Safe to re-run without disrupting etcd

#### Worker Nodes (`roles/k3s_worker`)
- ✅ Checks if k3s agent exists
- ✅ Verifies version and service state
- ✅ Only installs/upgrades when needed
- ✅ Ensures service is properly started

### Benefits

1. **Safe re-runs**: Run the playbook as many times as needed
   ```bash
   # This is now safe to run repeatedly
   ansible-playbook -i inventory/hosts.ini playbook.yaml
   ```

2. **Version upgrades**: Safely upgrade k3s versions
   ```bash
   # Update k3s_version in group_vars/all.yaml, then:
   ansible-playbook -i inventory/hosts.ini playbook.yaml
   ```

3. **Cluster recovery**: Re-apply configuration without reinstalling
   ```bash
   # Fix a misconfigured node without reinstalling k3s
   ansible-playbook -i inventory/hosts.ini playbook.yaml -l broken-node
   ```

4. **etcd Protection**: Won't disrupt the etcd database on re-runs

### Version Upgrade Example

```bash
# 1. Check current state
ansible-playbook -i inventory/hosts.ini connectivity-check.yaml

# 2. Update version in group_vars/all.yaml
vim group_vars/all.yaml  # Set k3s_version: "v1.28.5+k3s1"

# 3. Dry-run to see what will change
./scripts/dry-run.sh -i inventory/hosts.ini

# 4. Apply upgrade (masters first, one by one due to serial: 1)
ansible-playbook -i inventory/hosts.ini playbook.yaml
```

### Troubleshooting

If a node has issues, you can safely re-run:

```bash
# Check the problematic node
ansible-playbook -i inventory/hosts.ini connectivity-check.yaml -l worker-1

# Dry-run to see what would change
./scripts/dry-run.sh -i inventory/hosts.ini -l worker-1

# Re-apply configuration
ansible-playbook -i inventory/hosts.ini playbook.yaml -l worker-1
```

---

## 🚀 Complete Workflow Example

### New Cluster Deployment

```bash
# 1. Validate connectivity
ansible-playbook -i inventory/new-cluster.ini connectivity-check.yaml

# 2. Review what will be deployed
./scripts/dry-run.sh -i inventory/new-cluster.ini -o /tmp/new-cluster-plan.log

# 3. Review the plan
less /tmp/new-cluster-plan.log

# 4. Deploy the cluster
ansible-playbook -i inventory/new-cluster.ini playbook.yaml
```

### Production Update

```bash
# 1. Connectivity check
ansible-playbook -i inventory/production.ini connectivity-check.yaml

# 2. Dry-run with output saved
./scripts/dry-run.sh -i inventory/production.ini -o /tmp/prod-changes-$(date +%Y%m%d).log

# 3. Review changes with team
cat /tmp/prod-changes-*.log

# 4. Apply during maintenance window
ansible-playbook -i inventory/production.ini playbook.yaml
```

### Troubleshooting Issues

```bash
# 1. Check connectivity to problematic node
ansible-playbook -i inventory/hosts.ini connectivity-check.yaml -l broken-node -e connectivity_check_verbose=true

# 2. See what would change
./scripts/dry-run.sh -i inventory/hosts.ini -l broken-node -vv

# 3. Re-apply configuration (safe due to idempotency)
ansible-playbook -i inventory/hosts.ini playbook.yaml -l broken-node
```

---

## 📝 CI/CD Integration

Add these checks to your CI pipeline:

```yaml
# .github/workflows/deployment.yml
steps:
  - name: Connectivity Check
    run: |
      ansible-playbook -i inventory/staging.ini connectivity-check.yaml

  - name: Dry-Run
    run: |
      ./scripts/dry-run.sh -i inventory/staging.ini -o dry-run-output.log
      cat dry-run-output.log

  - name: Deploy
    run: |
      ansible-playbook -i inventory/staging.ini playbook.yaml
```

---

## ⚠️ Important Notes

1. **Dry-run limitations**: Some checks can't be predicted (e.g., network timeouts, race conditions)

2. **Token security**: Worker token is still redacted in logs (`no_log: true`)

3. **Serial execution**: Masters are deployed one at a time (`serial: 1`) to protect etcd

4. **Version detection**: k3s version check uses string matching on `--version` output

5. **Service state**: Checks rely on systemd, ensure systems use systemd

---

## 🎯 Quick Reference

| Task | Command |
|------|---------|
| Check connectivity | `ansible-playbook -i <inventory> connectivity-check.yaml` |
| Dry-run | `./scripts/dry-run.sh -i <inventory>` |
| Deploy | `ansible-playbook -i <inventory> playbook.yaml` |
| Upgrade version | Update `k3s_version`, then run playbook |
| Fix one node | Add `-l <node>` to any command |
| Verbose mode | Add `-v`, `-vv`, or `-vvv` |

---

**Need help?** Check the main [README.md](README.md) or open an issue.
