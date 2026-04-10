# k3s HA Architecture Reference

This document describes the recommended architecture for deploying Nebari on a high-availability k3s cluster across bare-metal or virtualized infrastructure. All site-specific values (IPs, hostnames, domain names) are shown as `<PLACEHOLDERS>` — replace them with values appropriate for your environment.

---

## Architecture Goals

- **High availability:** 3-node etcd control plane (tolerates 1 node failure)
- **Network isolation:** Cluster traffic confined to a private interface via Flannel interface binding and firewalld source zones; public interface drops all non-application traffic by default
- **Minimal attack surface:** NodePorts blocked, API server not directly reachable from the public network
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

| Interface | Purpose | Firewall behavior |
|---|---|---|
| `eth0` | Public — user access, internet egress | DROP by default (allowlist only) |
| `eth1` | Private — k3s cluster communication | ACCEPT via source-based zone |

> **Note:** Both interfaces share the same firewalld zone (DROP default). The private interface is opened selectively via a **source-based** zone (matched by CIDR), not by interface assignment. See [Section 5](#5-security-architecture).

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
[firewalld public zone — allowlisted sources only]
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

**Key principle:** MetalLB advertises LoadBalancer IPs on the private interface (`eth1`). Traffic reaches Traefik via the private network even when the upstream firewall forwards public traffic through NAT or a router.

---

## 3. k3s Configuration

### 3.1 Control plane — first server node (`--cluster-init`)

The first control-plane node bootstraps the embedded etcd cluster:

```bash
# /etc/systemd/system/k3s.service (first server)
ExecStart=/usr/local/bin/k3s server \
    --cluster-init                        \
    --token <CLUSTER_TOKEN>               \
    --tls-san <METALLB_VIP>              \  # include the MetalLB/ingress VIP in the TLS cert
    --flannel-iface eth1                  \  # pod traffic over private interface only
    --disable servicelb                   \  # use MetalLB instead
    --disable traefik                        # deploy Traefik separately via Helm
```

### 3.2 Control plane — additional server nodes

Subsequent control-plane nodes join the existing cluster:

```bash
# /etc/systemd/system/k3s.service (additional servers)
ExecStart=/usr/local/bin/k3s server \
    --token <CLUSTER_TOKEN>               \
    --server https://<FIRST_SERVER_PRIVATE_IP>:6443 \
    --tls-san <METALLB_VIP>              \
    --flannel-iface eth1                  \
    --disable servicelb                   \
    --disable traefik
```

> **API server access:** Workers and `kubectl` connect to a specific control-plane node's private IP (or a VIP if kube-vip is deployed). The `--tls-san` flag ensures the TLS certificate covers any stable IP or hostname used as the API endpoint. There is no `--bind-address` flag; firewall rules prevent API access from the public interface (see Section 5).

### 3.3 Worker nodes (agent)

```bash
# /etc/systemd/system/k3s-agent.service
ExecStart=/usr/local/bin/k3s agent \
    --token <CLUSTER_TOKEN>                              \
    --server https://<CONTROL_PLANE_PRIVATE_IP>:6443    \
    --flannel-iface eth1                                 \
    --node-ip <NODE_PRIVATE_IP>                          \  # optional: explicit binding
    --kubelet-arg address=<NODE_PRIVATE_IP>                 # optional: kubelet API on private IP
```

The `--node-ip` and `--kubelet-arg address=` flags are useful when a node has multiple interfaces and you want to ensure kubelet registers and listens on the private interface only.

### 3.4 Optional: kube-vip for API HA

kube-vip provides a floating virtual IP across the 3 control-plane nodes so that a single stable endpoint can be used for both `kubectl` and agent `--server`:

```yaml
# Deployed as a DaemonSet or static Pod on control-plane nodes
# virtual IP: <API_VIP> (on eth1 private subnet)
# mode: ARP
```

Without kube-vip, workers and operators connect to a specific control-plane node's private IP. This still provides HA for workloads (etcd quorum is maintained), but kubectl access is disrupted if that specific node goes down until DNS or kubeconfig is updated.

### 3.5 Embedded etcd

k3s embeds etcd automatically when `--cluster-init` is used on the first server node and additional nodes join with `--server`. The 3-node quorum tolerates one simultaneous node failure.

**Snapshot backup (k3s default):**

```bash
# Daily snapshots, retained for 7 days
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
    - <PRIVATE_IP_START>-<PRIVATE_IP_END>   # range on private subnet (eth1)
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

MetalLB speakers run as a DaemonSet on all nodes and respond to ARP requests for the IP pool on the private interface.

### Traefik Ingress Controller

Deployed via Helm into its own namespace. Key entrypoints:

| Entrypoint | Port | Notes |
|---|---|---|
| `web` | 80 | Redirects to `websecure` |
| `websecure` | 443 | TLS termination |
| `ssh` | 8022 | JupyterHub SSH (optional) |
| `sftp` | 8023 | JupyterHub SFTP (optional) |

**TLS enforcement pattern:** TLS is configured per-IngressRoute (not globally at the entrypoint level). Each route includes a `tls: {}` block. A catch-all IngressRoute handles unmatched requests with an HTTPS redirect middleware:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
spec:
  redirectScheme:
    scheme: https
    permanent: true
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: catch-all-redirect
spec:
  entryPoints:
    - websecure
  routes:
    - match: PathPrefix(`/`)
      kind: Rule
      services:
        - name: traefik
          port: 9000        # Traefik's own API as a dummy backend
      middlewares:
        - name: https-redirect
  tls: {}
```

### CoreDNS

Embedded in k3s. Service IP: `10.43.0.10` (k3s default). Forwards external queries to upstream resolvers configured in the node's `/etc/resolv.conf`.

### Kyverno (Policy Engine)

Enforces baseline Pod Security Standards and custom policies (resource limits, image pull policies). Deploy via Helm before workloads.

---

## 5. Security Architecture

### 5.1 Firewall zones (firewalld)

The firewall uses two active zones:

#### Public zone — default DROP (both interfaces)

Both `eth0` and `eth1` are assigned to the public zone with a DROP target. Access is granted selectively via source allowlisting:

```bash
# Set zone target to DROP
firewall-cmd --zone=public --set-target=DROP

# Allow application services
firewall-cmd --zone=public --add-service=http
firewall-cmd --zone=public --add-service=https
firewall-cmd --zone=public --add-service=ssh

# Allowlist specific source CIDRs (all node IPs, pod/service CIDRs)
firewall-cmd --zone=public --add-source=<NODE_PUBLIC_IP>
firewall-cmd --zone=public --add-source=10.42.0.0/16   # pod network
firewall-cmd --zone=public --add-source=10.43.0.0/16   # service network
firewall-cmd --zone=public --add-source=<PRIVATE_SUBNET>

# Also allowlist individual admin/operator IPs as needed
firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="<ADMIN_IP>" accept'
```

#### internal-k8s zone — ACCEPT (source-based, not interface-based)

This zone matches by **source CIDR** (the private subnet), not by interface. This is key: traffic arriving on `eth1` from cluster nodes is allowed because their source IPs fall within the private subnet:

```bash
firewall-cmd --new-zone=internal-k8s --permanent
firewall-cmd --zone=internal-k8s --set-target=ACCEPT --permanent
firewall-cmd --zone=internal-k8s --add-source=<PRIVATE_SUBNET> --permanent
firewall-cmd --zone=internal-k8s --add-port=6443/tcp --permanent    # Kubernetes API
firewall-cmd --zone=internal-k8s --add-port=2379-2380/tcp --permanent  # etcd
firewall-cmd --zone=internal-k8s --add-port=10250/tcp --permanent   # kubelet
firewall-cmd --zone=internal-k8s --add-port=8472/udp --permanent    # Flannel VXLAN
firewall-cmd --zone=internal-k8s --add-port=7946/tcp --permanent    # MetalLB memberlist
firewall-cmd --zone=internal-k8s --add-port=7946/udp --permanent
firewall-cmd --zone=internal-k8s --add-port=9100/tcp --permanent    # node-exporter
firewall-cmd --reload
```

### 5.2 Block NodePorts on the public interface

NodePort services (30000–32767) must never be reachable from outside. Apply both approaches for defense in depth:

**Rich rules (firewalld public zone — REJECT with ICMP response):**

```bash
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" port port="30000-32767" protocol="tcp" reject'
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" port port="30000-32767" protocol="udp" reject'
```

**Raw PREROUTING rules (drop before connection tracking — applied via firewalld direct rules):**

```bash
firewall-cmd --permanent --direct --add-rule ipv4 raw PREROUTING 0 \
  -i eth0 -p tcp --dport 30000:32767 -j DROP
firewall-cmd --permanent --direct --add-rule ipv4 raw PREROUTING 0 \
  -i eth0 -p udp --dport 30000:32767 -j DROP
firewall-cmd --reload
```

The raw rules act before connection tracking and complement the rich rules, which apply after.

### 5.3 TLS

| Layer | Mechanism |
|---|---|
| Public ingress | TLS 1.2+ via Traefik per-IngressRoute; HSTS enforced |
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
# Update server address to private IP (or API VIP if using kube-vip)
sed -i 's/127.0.0.1/<CONTROL_PLANE_PRIVATE_IP>/' ~/.kube/config
```

### Checking cluster health

```bash
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
k3s etcd-snapshot list
```

### Upgrading k3s

Test upgrades in a staging environment first. Use the [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) for rolling upgrades:

```bash
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
```

---

## 8. Related Documentation

- [k3s upstream docs](https://docs.k3s.io)
- [MetalLB docs](https://metallb.universe.tf)
- [Traefik docs](https://doc.traefik.io/traefik)
- [kube-vip docs](https://kube-vip.io)
- [firewalld docs](https://firewalld.org/documentation)
