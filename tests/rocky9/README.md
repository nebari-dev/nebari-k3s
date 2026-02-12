
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
- VirtualBox or QEMU (macOS)
- Ansible (run from repo root)

The default box is `generic/rocky9` which supports multiple providers.

## Bring up / destroy

```bash
cd tests/rocky9
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
ansible-playbook -i tests/rocky9/inventories/hosts.ini playbook.yaml
```

If you need to force python path:

```bash
ansible-playbook -i tests/rocky9/inventories/hosts.ini playbook.yaml \
  -e ansible_python_interpreter=/usr/bin/python3
```

## Key variables (group_vars)

This lab assumes:

* `flannel_iface: eth1` (Vagrant private NIC)
* `apiserver_endpoint: 192.168.56.10`
* `k3s_node_cidrs: [192.168.56.0/24]`
* `metal_lb_ip_range: "192.168.56.200-192.168.56.210"`

See: `tests/rocky9/group_vars/all.yaml`

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
