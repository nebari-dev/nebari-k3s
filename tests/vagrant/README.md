
# Rocky Linux 9 test lab (RHEL-like) — K3s HA (3 CP) + 2 workers

This folder provides a repeatable Vagrant environment using **Rocky Linux 9** to test the Ansible playbook and security
hardening (firewalld/open ports) in a RHEL-like system.

## Topology

Single cluster on a private network:

- VIP / apiserver endpoint: `192.168.56.10`
- Control planes (3):
  - cp1: `192.168.56.11`
  - cp2: `192.168.56.12`
  - cp3: `192.168.56.13`
- Workers (2):
  - w1: `192.168.56.21`
  - w2: `192.168.56.22`
- MetalLB pool: `192.168.56.200-192.168.56.210`

## Requirements

- Vagrant
- **Linux**: libvirt (recommended) or VirtualBox
- **macOS Intel**: VirtualBox
- **macOS Apple Silicon**: ⚠️ Not supported - see below
- Ansible (run from repo root)

The default box is `generic/rocky9` which supports multiple providers.

### ⚠️ macOS Apple Silicon Users

Vagrant with QEMU has severe limitations on Apple Silicon:
- **Memory limit**: Max 2GB per VM (highmem=off constraint)
- **SSH timeouts**: Frequently hangs during provisioning
- **No networking**: QEMU provider doesn't support `vm.network` configs
- **Docker provider**: Containers exit immediately (systemd incompatibility)

**Recommended alternatives:**
1. 🌐 **Cloud VMs** (DigitalOcean, Hetzner, Linode) - $6-10/month, realistic testing
2. 🐳 **Docker testing**: `./scripts/test-docker.sh` for syntax validation only
3. 🤖 **GitHub Actions**: Push to branch and let CI validate

See [macOS Testing Guide](../../docs/macos-testing.md) for cloud setup instructions.

**TL;DR**: Local testing on Apple Silicon is not practical - use cloud VMs.

## Bring up / destroy

```bash
cd tests/vagrant
vagrant up
vagrant status
````

Destroy all VMs for this platform:

```bash
vagrant destroy -f
```

## Run Ansible against this lab

From the **repo root**:

```bash
ansible-playbook -i tests/vagrant/hosts.ini playbook.yaml
```

If you need to force python path:

```bash
ansible-playbook -i tests/vagrant/hosts.ini playbook.yaml \
  -e ansible_python_interpreter=/usr/bin/python3
```

## Key variables (group_vars)

This lab assumes:

* `flannel_iface: eth1` (Vagrant private NIC)
* `apiserver_endpoint: 192.168.56.10`
* `k3s_node_cidrs: [192.168.56.0/24]`
* `metal_lb_ip_range: "192.168.56.200-192.168.56.210"`

See: `tests/vagrant/hosts.ini` [k3s_cluster:vars] section

## Security testing quick commands

From your host:

```bash
nmap -sS -sV -Pn -p 22,80,443,6443,8472,51820,7946,10250 192.168.56.11
nmap -sS -sV -Pn -p 22,80,443,6443,10250 192.168.56.21
```

From inside a node:

```bash
sudo firewall-cmd --state
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all
sudo ss -tulpn
```

## Notes / gotchas

* Rocky uses **firewalld** by default and is the best place to validate your `firewall_secure` role behavior.
* If HA breaks under tight firewall rules, confirm control-plane-to-control-plane connectivity (etcd/cluster traffic).
* If networking assertions fail, double-check `flannel_iface` exists and has IPv4 (commonly `eth1` in Vagrant).
