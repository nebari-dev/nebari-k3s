# Documentation Index

Welcome to the K3s deployment documentation. This collection provides comprehensive guides for deploying, configuring, and managing your K3s cluster.

## 📚 Documentation Structure

### Getting Started

- **[README](../README.md)** - Quick start guide and overview
- **[CHANGES](../CHANGES.md)** - Summary of security enhancements

### Configuration

- **[Configuration Variables](configuration-variables.md)** - Complete reference of all configuration options
- **[Network Configuration](network-configuration.md)** - CNI setup, service networking, and troubleshooting
- **[Storage Options](storage-options.md)** - Storage backends, provisioners, and migration strategies

### Security

- **[Security Guide](../SECURITY.md)** - Comprehensive security configuration and best practices
- **[Migration Guide](../MIGRATION.md)** - Safe upgrade path for existing deployments
- **[Quick Reference](../QUICK-REFERENCE.md)** - Command cheat sheet for daily operations

### Examples

- **[Inventory Examples](../INVENTORY-EXAMPLE.md)** - Sample inventory configurations

---

## 🎯 Quick Navigation

### I want to...

**Deploy a new cluster**
1. Read [README](../README.md) for overview
2. Configure [Configuration Variables](configuration-variables.md)
3. Set up [Network Configuration](network-configuration.md)
4. Choose [Storage Options](storage-options.md)
5. Review [Security Guide](../SECURITY.md)
6. Deploy!

**Upgrade existing cluster**
1. Review [CHANGES](../CHANGES.md)
2. Follow [Migration Guide](../MIGRATION.md)
3. Use [Quick Reference](../QUICK-REFERENCE.md) for troubleshooting

**Configure storage**
1. Read [Storage Options](storage-options.md)
2. Choose backend (local-path, Longhorn, NFS, Ceph)
3. Follow migration guide if changing storage

**Troubleshoot networking**
1. Check [Network Configuration](network-configuration.md) troubleshooting section
2. Use [Quick Reference](../QUICK-REFERENCE.md) for diagnostic commands
3. Review [Security Guide](../SECURITY.md) for firewall issues

**Understand security**
1. Read [Security Guide](../SECURITY.md) for architecture
2. Review [Configuration Variables](configuration-variables.md) for security settings
3. Use [Quick Reference](../QUICK-REFERENCE.md) for validation

---

## 📖 Document Descriptions

### Configuration Variables
**File**: `configuration-variables.md`  
**Length**: ~600 lines  
**Topics**: Core K3s settings, network config, security settings, HA, MetalLB, Kube-VIP, component toggles

**When to use**: Setting up cluster configuration, understanding available options, troubleshooting settings

**Key sections**:
- Core K3s Settings (version, token, server args)
- Network Configuration (interfaces, CIDRs, Flannel)
- Security Settings (admin CIDRs, ingress, NodePorts)
- High Availability (embedded etcd, VIP)
- MetalLB & Kube-VIP configuration
- Variable override hierarchy

---

### Network Configuration
**File**: `network-configuration.md`  
**Length**: ~550 lines  
**Topics**: Network architecture, CNI options, Flannel backends, services, ingress, network policies, troubleshooting

**When to use**: Setting up pod networking, configuring ingress, troubleshooting connectivity issues

**Key sections**:
- Network Architecture (components, default ranges)
- CNI Configuration (Flannel interface selection)
- Flannel Backends (vxlan, wireguard, host-gw)
- Service Networking (ClusterIP, NodePort, LoadBalancer)
- MetalLB Configuration (Layer 2, BGP)
- Ingress Setup (NGINX, Traefik)
- Network Policies (examples, troubleshooting)
- Troubleshooting guide

---

### Storage Options
**File**: `storage-options.md`  
**Length**: ~500 lines  
**Topics**: Default storage, local-path, Longhorn, NFS, Rook-Ceph, migration

**When to use**: Choosing storage backend, migrating storage, setting up persistent volumes

**Key sections**:
- Default K3s Storage (local-path provisioner)
- Local Path Provisioner (custom configurations)
- Longhorn (distributed block storage)
- NFS Storage (shared storage setup)
- Rook-Ceph (enterprise distributed storage)
- Migration Strategies (between storage types)
- Storage comparison table

---

### Security Guide
**File**: `../SECURITY.md`  
**Length**: ~380 lines  
**Topics**: Firewall zones, port security, access control, best practices, compliance

**When to use**: Understanding security architecture, configuring firewalls, validating security posture

**Key sections**:
- Security Improvements Overview
- Dedicated K3s Cluster Zone
- Public Zone Restrictions
- NodePort Security
- Admin Access Control
- Configuration Variables
- Deployment Checklist
- Validation Commands
- Security Best Practices
- Troubleshooting

---

### Migration Guide
**File**: `../MIGRATION.md`  
**Length**: ~380 lines  
**Topics**: Safe upgrade process, pre-migration checks, rollback procedures, common issues

**When to use**: Upgrading from old firewall configuration to new secure setup

**Key sections**:
- Pre-Migration Checklist
- Backup Procedures
- Configuration Updates
- Testing Process (dry run → single node → all nodes)
- Post-Migration Validation
- Rollback Procedures
- Common Issues & Fixes
- Performance Impact Notes

---

### Quick Reference
**File**: `../QUICK-REFERENCE.md`  
**Length**: ~380 lines  
**Topics**: Command cheat sheet, diagnostic tools, emergency procedures

**When to use**: Daily operations, troubleshooting, quick fixes

**Key sections**:
- Firewall zone commands
- Port operations (allow, block, temporary)
- Diagnostic commands (ss, nc, firewall-cmd)
- Log viewing and analysis
- Emergency access recovery
- Monitoring & auditing commands
- Common fixes
- Security validation tests
- Ansible quick commands

---

### Inventory Examples
**File**: `../INVENTORY-EXAMPLE.md`  
**Length**: ~370 lines  
**Topics**: Sample inventories, connection setup, network planning

**When to use**: Creating initial inventory, setting up Ansible connection

**Key sections**:
- Inventory structure examples
- Production vs development configs
- Group variables setup
- Network planning worksheet
- Ansible connection troubleshooting
- SSH key setup
- Bastion host configuration
- Verification commands

---

## 🔍 Topic Index

### By Feature

**Networking**
- [Network Configuration](network-configuration.md) - Complete networking guide
- [Configuration Variables](configuration-variables.md#network-configuration) - Network variables reference

**Storage**
- [Storage Options](storage-options.md) - All storage backends
- [Configuration Variables](configuration-variables.md#advanced-settings) - Storage-related variables

**Security**
- [Security Guide](../SECURITY.md) - Security architecture and best practices
- [Configuration Variables](configuration-variables.md#security-settings) - Security variables
- [Quick Reference](../QUICK-REFERENCE.md) - Security commands

**High Availability**
- [Configuration Variables](configuration-variables.md#high-availability) - HA settings
- [Network Configuration](network-configuration.md#service-networking) - LoadBalancer and VIP

**Troubleshooting**
- [Network Configuration](network-configuration.md#troubleshooting) - Network issues
- [Quick Reference](../QUICK-REFERENCE.md) - Diagnostic commands
- [Migration Guide](../MIGRATION.md#common-migration-issues) - Migration issues

---

## 📝 Contributing to Documentation

When adding or updating documentation:

1. **Maintain structure**: Follow existing format and organization
2. **Update index**: Add new documents to this index
3. **Cross-reference**: Link to related documents
4. **Include examples**: Provide practical code examples
5. **Test commands**: Verify all commands work
6. **Update README**: Reflect changes in main README

---

## 🆘 Getting Help

1. **Search documentation**: Use Ctrl+F in relevant doc
2. **Check examples**: Look for similar use cases
3. **Review troubleshooting**: Check troubleshooting sections
4. **Validate configuration**: Use validation commands
5. **Check logs**: Review firewalld and K3s logs

---

## 📄 Document Templates

### New Configuration Document

```markdown
# Document Title

Brief description of what this document covers.

## Table of Contents

- [Section 1](#section-1)
- [Section 2](#section-2)

---

## Section 1

Content with examples...

## See Also

- [Related Doc 1](link)
- [Related Doc 2](link)
```

### New Troubleshooting Entry

```markdown
### Issue: Description

**Symptoms**: What the user sees

**Cause**: Why it happens

**Debug**:
```bash
# Commands to diagnose
command here
```

**Fix**:
```bash
# Commands to fix
command here
```
```

---

Last updated: February 2026
