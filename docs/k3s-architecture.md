# k3s HA Architecture Reference

This document describes the recommended architecture for deploying Nebari on a high-availability k3s cluster across bare-metal or virtualized infrastructure. All site-specific values (IPs, hostnames, domain names) are shown as `<PLACEHOLDERS>` — replace them with values appropriate for your environment.

---

## Architecture Goals

- **High availability:** 3-node etcd control plane (tolerates 1 node failure)
- **Network isolation:** Kubernetes API and cluster traffic confined to a private interface; public interface drops all non-application traffic by default
- **Minimal attack surface:** NodePorts blocked, API server never exposed publicly
- **Reproducibility:** k3s systemd flags documented for consistent re-deployment

---

## 1. Node Topology

### Recommended layout

| Role | Count | vCPU | RAM | Notes |
|---|---|---|---|---|
| Control plane | 3 | 8 | 32 GB | One per physical host for fault isolation |
| Worker (general) | N | 8–16 | 32–64 GB | General-purpose workloads |
| Worker (GPU, optional) | N | 8–16 | 32–64 GB | Attach GPU devices via passthrough/vfio |

All nodes run **Red Hat Enterprise Linux 9.x** (or compatible) with SELinux in enforcing mode.

### Network interfaces

Each node has two interfaces:

| Interface | Purpose | Default firewall zone |
|---|---|---|
| `eth0` | Public — user access, internet egress | DROP (allowlist only) |
| `eth1` | Private — k3s cluster communication | ACCEPT |

---

## 2. Network Architecture

### Address plan

| Network | CIDR | Description |
|---|---|---|
| Public | `<PUBLIC_SUBNET>` | External access (managed upstream) |
| Private (cluster) | `<PRIVATE_SUBNET>` e.g. `192.168.100.0/24` | Node-to-node communication, etcd, API |
| Pod network | `10.42.0.0/16` | Flannel VXLAN overlay (k3s default) |
| Service network | `10.43.0.0/16` | ClusterIP services (k3s default) |
| MetalLB pool | `<PRIVATE_IP_RANGE>` | LoadBalancer IPs on the private subnet |

Each node is assigned a `/24` slice from the pod CIDR by Flannel automatically.

### Traffic flow

```
Internet
    │ HTTPS/443, HTTP/80
    ▼
[Upstream Firewall / NAT]
    │
    ▼ eth0 (public — DROP default)
[firewalld public zone]
    │ allowed: http, https, ssh
    ▼
MetalLB LoadBalancer IP (private subnet, eth1)
    │
    ▼
Traefik Ingress Controller
    │
    ├──► JupyterHub   (ClusterIP)
    ├──► Keycloak     (ClusterIP)
    ├──► Grafana      (ClusterIP)
    └──► Other apps   (ClusterIP)
              │
              ▼
        Pod Network (10.42.0.0/16)
```

**Key principle:** MetalLB advertises LoadBalancer IPs on `eth1` (private). Traffic reaches Traefik via the private network even when the upstream firewall forwards public traffic to a private IP through NAT or a router.

---

## 3. k3s Configuration

### 3.1 Control plane (server nodes)

```bash
# /etc/systemd/system/k3s.service.d/override.conf
ExecStart=/usr/local/bin/k3s server \
  --bind-address=<PRIVATE_IP>       \  # listen on eth1 only
  --advertise-address=<PRIVATE_IP>  \
  --node-ip=<PRIVATE_IP>            \
  --flannel-iface=eth1              \  # pod traffic over private interface
  --tls-san=<CONTROL_PLANE_1_IP>   \  # include all control-plane private IPs
  --tls-san=<CONTROL_PLANE_2_IP>   \
  --tls-san=<CONTROL_PLANE_3_IP>   \
  --tls-san=<VIP>                  \  # kube-vip virtual IP (optional)
  --disable=traefik                 \  # deploy Traefik separately (Helm)
  --disable=servicelb                  # use MetalLB instead
```

**Security rationale:** `--bind-address` limits the API server (port 6443) to the private interface. The Kubernetes API is never reachable from `eth0`.

### 3.2 Worker nodes (agent)

```bash
ExecStart=/usr/local/bin/k3s agent \
  --server=https://<CONTROL_PLANE_IP_OR_VIP>:6443 \
  --node-ip=<PRIVATE_IP>                           \
  --flannel-iface=eth1
```

### 3.3 High availability with kube-vip

kube-vip provides a floating virtual IP across the 3 control-plane nodes so workers and `kubectl` can use a single stable endpoint:

```yaml
# deployed as a DaemonSet on control-plane nodes
# virtual IP: <VIP> (on eth1)
# mode: ARP
```

See [kube-vip docs](https://kube-vip.io) for the full static Pod manifest.

### 3.4 Embedded etcd

k3s embeds etcd automatically when `--cluster-init` is used on the first server node and additional nodes join with `--server`. The 3-node quorum tolerates one simultaneous node failure.

**Snapshot backup:**

```bash
# k3s default: daily snapshots retained for 7 days
# Location: /var/lib/rancher/k3s/server/db/snapshots/
```

---

## 4. Cluster Add-ons

### MetalLB (Layer 2)

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - <PRIVATE_IP_START>-<PRIVATE_IP_END>   # range on eth1 subnet
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

MetalLB speakers run as a DaemonSet on all nodes and respond to ARP requests for the IP pool addresses.

### Traefik Ingress Controller

Deployed via Helm into its own namespace. Key entrypoints:

| Entrypoint | Port | Notes |
|---|---|---|
| `web` | 80 | Redirects to `websecure` |
| `websecure` | 443 | TLS termination |
| `ssh` | 8022 | JupyterHub SSH (optional) |
| `sftp` | 8023 | JupyterHub SFTP (optional) |

TLS certificates are managed externally (e.g. Let's Encrypt via cert-manager) and stored as Kubernetes Secrets referenced by IngressRoute CRDs.

### CoreDNS

Embedded in k3s. Service IP: `10.43.0.10` (k3s default). Forwards external queries to upstream resolvers configured in the node's `/etc/resolv.conf`.

### Kyverno (Policy Engine)

Enforces baseline Pod Security Standards and custom policies (resource limits, image pull policies). Deploy via Helm before workloads.

---

## 5. Security Architecture

### 5.1 Firewall zones (firewalld)

#### Public zone (eth0) — default DROP

```bash
firewall-cmd --zone=public --set-target=DROP
firewall-cmd --zone=public --add-service=http
firewall-cmd --zone=public --add-service=https
firewall-cmd --zone=public --add-service=ssh
# Add source allowlists as needed:
firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="<ALLOWED_CIDR>" accept'
```

#### Internal-k8s zone (eth1 / private subnet) — ACCEPT

```bash
firewall-cmd --zone=internal --add-port=6443/tcp    # Kubernetes API
firewall-cmd --zone=internal --add-port=2379-2380/tcp  # etcd
firewall-cmd --zone=internal --add-port=10250/tcp   # kubelet
firewall-cmd --zone=internal --add-port=8472/udp    # Flannel VXLAN
firewall-cmd --zone=internal --add-port=7946/tcp    # MetalLB memberlist
firewall-cmd --zone=internal --add-port=7946/udp
```

### 5.2 Block NodePorts on the public interface

NodePort services (30000–32767) must never be reachable from outside. Apply these raw iptables rules (survives firewalld restarts when added via direct rules):

```bash
firewall-cmd --direct --add-rule ipv4 raw PREROUTING 0 \
  -i eth0 -p tcp --dport 30000:32767 -j DROP

firewall-cmd --direct --add-rule ipv4 raw PREROUTING 0 \
  -i eth0 -p udp --dport 30000:32767 -j DROP
```

### 5.3 TLS

| Layer | Mechanism |
|---|---|
| Public ingress | TLS 1.2+ via Traefik; HSTS enforced |
| etcd peer | Mutual TLS (auto-generated by k3s) |
| kubelet → API | Client certificate authentication |

### 5.4 SELinux

Run all nodes with SELinux in **enforcing** mode (`targeted` policy). containerd runs containers in the `container_t` domain. Verify with:

```bash
getenforce       # should return "Enforcing"
sestatus         # confirm policy type
```

---

## 6. High Availability & Failure Scenarios

| Failure | User impact | Recovery |
|---|---|---|
| 1 control-plane node | None (etcd quorum maintained) | Auto-rejoin on reboot |
| 2 control-plane nodes | API unavailable | Manual intervention |
| 1 worker node | Running pods evicted and rescheduled | kubelet auto-rejoins |
| MetalLB speaker crash | None (other speakers take over) | DaemonSet auto-restarts |
| Traefik pod crash | Brief downtime (~10s) | Deployment auto-restarts |

---

## 7. Operations

### kubectl access

```bash
# Copy kubeconfig from any control-plane node
scp <CONTROL_PLANE_1>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Update server address to private IP or VIP
sed -i 's/127.0.0.1/<CONTROL_PLANE_IP_OR_VIP>/' ~/.kube/config
```

### Checking cluster health

```bash
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
k3s etcd-snapshot list
```

### Upgrading k3s

Test upgrades in a staging/digital-twin environment first. Use the [k3s upgrade operator](https://github.com/rancher/system-upgrade-controller) for rolling upgrades:

```bash
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
```

---

## 8. Related Documentation

- [network-configuration.md](network-configuration.md) — detailed network setup guide
- [security-hardening.md](security-hardening.md) — hardening checklist
- [k3s upstream docs](https://docs.k3s.io)
- [MetalLB docs](https://metallb.universe.tf)
- [kube-vip docs](https://kube-vip.io)
- [Traefik docs](https://doc.traefik.io/traefik)
