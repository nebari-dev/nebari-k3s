# Network Configuration Guide

This document explains K3s networking configuration, CNI options, and network troubleshooting.

## Table of Contents

- [Network Architecture](#network-architecture)
- [CNI Configuration](#cni-configuration)
- [Flannel Backends](#flannel-backends)
- [Service Networking](#service-networking)
- [Ingress Configuration](#ingress-configuration)
- [Network Policies](#network-policies)
- [Troubleshooting](#troubleshooting)

---

## Network Architecture

### K3s Network Components

```
┌─────────────────────────────────────────────────────────────┐
│                    K3s Network Stack                         │
├─────────────────────────────────────────────────────────────┤
│  Application Layer                                           │
│  ├─ Ingress (External traffic → Services)                   │
│  └─ LoadBalancer (MetalLB)                                  │
├─────────────────────────────────────────────────────────────┤
│  Service Layer                                               │
│  ├─ ClusterIP (Internal service discovery)                  │
│  ├─ NodePort (External access via nodes)                    │
│  └─ LoadBalancer (External IP assignment)                   │
├─────────────────────────────────────────────────────────────┤
│  CNI Layer (Flannel)                                        │
│  ├─ Pod-to-Pod communication                                │
│  ├─ Cross-node networking                                   │
│  └─ Network policies (with kube-router)                     │
├─────────────────────────────────────────────────────────────┤
│  Host Network                                                │
│  ├─ Node interfaces (eth0, eth1, etc.)                     │
│  └─ Host routing and firewall                              │
└─────────────────────────────────────────────────────────────┘
```

### Default Network Ranges

| Network | CIDR | Purpose |
|---------|------|---------|
| **Pod Network** | `10.42.0.0/16` | Pod IP addresses |
| **Service Network** | `10.43.0.0/16` | Service ClusterIPs |
| **Node Network** | Your network | Node-to-node communication |

### Customizing Network Ranges

Add to `extra_server_args` in `group_vars/all.yaml`:

```yaml
extra_server_args: >-
  --cluster-cidr 10.50.0.0/16
  --service-cidr 10.51.0.0/16
  --cluster-dns 10.51.0.10
  {{ other_args }}
```

⚠️ **Warning**: Cannot be changed after cluster creation!

---

## CNI Configuration

K3s uses **Flannel** as the default CNI (Container Network Interface).

### Flannel Configuration

Flannel is automatically configured by K3s. Key configuration:

**Variable**: `flannel_iface`  
**Location**: `group_vars/all.yaml`

```yaml
flannel_iface: eth1  # Interface for pod networking
```

### Determining Correct Interface

```bash
# On each node, run:
ip -br addr show

# Example output:
# lo        UNKNOWN  127.0.0.1/8
# eth0      UP       146.165.244.3/21     <- Public/External
# eth1      UP       10.11.0.33/24        <- Internal/Cluster (USE THIS)
```

**Rules**:
- Use the interface on the **cluster internal network**
- Must be reachable from all nodes
- Should have adequate bandwidth for pod traffic

### Disabling Flannel (Advanced)

To use alternative CNI (Calico, Cilium, etc.):

```yaml
extra_server_args: >-
  --flannel-backend=none
  {{ other_args }}
```

Then install your preferred CNI manually.

---

## Flannel Backends

Flannel supports multiple backend types for pod networking.

### Backend Comparison

| Backend | Encapsulation | Encryption | Performance | Use Case |
|---------|---------------|------------|-------------|----------|
| **vxlan** | Yes (UDP 8472) | ❌ No | ⭐⭐⭐⭐ Good | Default, works everywhere |
| **wireguard** | Yes (UDP 51820) | ✅ Yes | ⭐⭐⭐⭐ Good | Security-focused |
| **host-gw** | No (direct routing) | ❌ No | ⭐⭐⭐⭐⭐ Excellent | Same L2 network required |
| **ipsec** | Yes (ESP) | ✅ Yes | ⭐⭐⭐ Moderate | Legacy encryption |

### VXLAN (Default)

**Configuration**:
```yaml
k3s_flannel_backend: vxlan
```

**Firewall Requirements**:
- UDP port 8472 (node-to-node)

**Pros**: Works in all environments, including across L3 boundaries

**Cons**: Small overhead from encapsulation (~50 bytes)

---

### WireGuard

**Configuration**:
```yaml
k3s_flannel_backend: wireguard
```

**Prerequisites**:
```bash
# Install WireGuard kernel module (Rocky Linux 9)
ansible all -i hosts.ini -m shell -a "dnf install -y wireguard-tools"
```

**Firewall Requirements**:
- UDP port 51820 (node-to-node)
- UDP port 51821 (if IPv6 enabled)

**Pros**: 
- Encrypted pod traffic
- Modern, fast encryption
- Minimal overhead

**Cons**: 
- Requires WireGuard kernel support (Linux 5.6+)
- Additional firewall rules

**Enable in Playbook**:
```yaml
k3s_flannel_backend: wireguard
k3s_enable_ipv6: false  # or true for IPv6

extra_server_args: >-
  --flannel-backend=wireguard
  --flannel-iface={{ flannel_iface }}
```

---

### host-gw (Direct Routing)

**Configuration**:
```yaml
k3s_flannel_backend: host-gw
```

**Requirements**:
- All nodes on same L2 network (same broadcast domain)
- No firewalls between nodes blocking pod traffic

**Firewall Requirements**:
- None (direct routing, no encapsulation)
- Must allow pod CIDR traffic (10.42.0.0/16 by default)

**Pros**: 
- Best performance (no overhead)
- No encapsulation

**Cons**: 
- Only works on same L2 network
- No support for complex network topologies

**Configuration**:
```yaml
extra_server_args: >-
  --flannel-backend=host-gw
  --flannel-iface={{ flannel_iface }}
```

---

## Service Networking

### Service Types

#### ClusterIP (Default)

Internal-only service, accessible from within cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
```

**Access**: `my-service.namespace.svc.cluster.local:80`

---

#### NodePort

Exposes service on each node's IP at a static port (30000-32767).

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080  # Optional, auto-assigned if omitted
```

**Access**: `<any-node-ip>:30080`

**Security**: By default, NodePorts are blocked in public firewall zone. Only accessible from admin CIDRs.

**Configuration**:
```yaml
# In group_vars/all.yaml
k3s_expose_nodeports_publicly: false  # Keep blocked
k3s_allow_nodeports_from_admin: true  # Allow from admin CIDRs
```

---

#### LoadBalancer (via MetalLB)

Assigns external IP address to service.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
```

**Access**: `<external-ip>:80` (IP from MetalLB pool)

**Requirements**: MetalLB must be installed and configured.

**Configuration**:
```yaml
# In group_vars/all.yaml
k3s_enable_metallb: true
metal_lb_ip_range: 10.11.0.191-10.11.0.199  # Available IPs
metal_lb_mode: layer2  # or bgp
```

---

### MetalLB Configuration

MetalLB provides LoadBalancer service support for bare-metal clusters.

#### Layer 2 Mode (Default)

**How it works**:
1. MetalLB assigns IP from pool to service
2. Leader node responds to ARP requests for that IP
3. Traffic flows to leader node, then kube-proxy routes to pods

**Pros**: Simple, no router configuration needed

**Cons**: Limited to single node (leader), no load distribution

**Configuration**:
```yaml
metal_lb_mode: layer2
metal_lb_ip_range: 10.11.0.191-10.11.0.199
```

**Firewall Requirements**:
- TCP/UDP 7946 (node-to-node memberlist)
- TCP 7472 (speaker API)
- Allow ARP traffic

---

#### BGP Mode (Advanced)

**How it works**:
1. MetalLB peers with network routers via BGP
2. Announces service IPs to routers
3. Router distributes traffic across all nodes

**Pros**: True load distribution, multiple paths

**Cons**: Requires BGP-capable routers and configuration

**Configuration**:
```yaml
metal_lb_mode: bgp
```

Then configure BGP peers manually via ConfigMap or CRDs.

---

### Service Discovery

Kubernetes provides built-in DNS for service discovery:

```bash
# Service FQDN format
<service-name>.<namespace>.svc.cluster.local

# Examples
kubectl run test --image=busybox --rm -it -- sh
/ # nslookup my-service.default.svc.cluster.local
/ # wget -O- http://my-service.default.svc.cluster.local
```

**DNS Server**: CoreDNS (included with K3s)  
**DNS Service IP**: `10.43.0.10` (by default)

---

## Ingress Configuration

K3s disables Traefik by default in this setup. Install your preferred ingress controller.

### NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

### Traefik (Alternative)

If you want to use Traefik, remove `--disable traefik` from `extra_server_args` or install manually:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --set service.type=LoadBalancer
```

### Example Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
  tls:
  - hosts:
    - app.example.com
    secretName: tls-secret
```

### Ingress Firewall Configuration

Control external access to ingress:

```yaml
# In group_vars/all.yaml

# Allow from everywhere
k3s_expose_ingress_publicly: true
k3s_ingress_allowed_cidrs: []

# Or restrict to specific networks
k3s_expose_ingress_publicly: true
k3s_ingress_allowed_cidrs:
  - 203.0.113.0/24
  - 198.51.100.0/24
```

---

## Network Policies

K3s uses **kube-router** for Network Policy enforcement.

### Default Deny Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

### Allow Specific Traffic

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### Allow from Ingress Controller

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
```

### Monitoring Network Policies

```bash
# View network policies
kubectl get networkpolicies -A

# Check kube-router logs
kubectl logs -n kube-system -l k8s-app=kube-router

# View iptables rules created by policies
sudo iptables -L -n -v | grep KUBE-NWPLCY
```

---

## Troubleshooting

### Pod Cannot Connect to Service

**Symptoms**: `nslookup` works but connection fails

**Debug**:
```bash
# Check service endpoints
kubectl get endpoints my-service

# If no endpoints, check pod selector
kubectl get pods -l app=my-app

# Check service definition
kubectl describe service my-service

# Test from another pod
kubectl run test --image=busybox --rm -it -- wget -O- http://my-service
```

---

### Pod Cannot Reach External Network

**Symptoms**: Can reach services but not internet

**Debug**:
```bash
# Check masquerading is enabled
sudo firewall-cmd --zone=public --query-masquerade

# Enable if needed
sudo firewall-cmd --permanent --zone=public --add-masquerade
sudo firewall-cmd --reload

# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# Check DNS
kubectl exec -it test-pod -- nslookup google.com
```

---

### Nodes Cannot Communicate

**Symptoms**: Pods scheduled on different nodes cannot connect

**Debug**:
```bash
# Check Flannel is running
kubectl get pods -n kube-system -l app=flannel

# Check Flannel interface exists
ip addr show flannel.1

# Check Flannel routes
ip route | grep 10.42

# Test connectivity between nodes on Flannel port
# From node-01 to node-02
nc -zv 10.11.0.32 8472  # vxlan
nc -zv 10.11.0.32 51820 # wireguard

# Check firewall allows Flannel
sudo firewall-cmd --zone=k3s-cluster --list-all
```

---

### MetalLB Not Assigning IPs

**Symptoms**: LoadBalancer service stuck in `<pending>`

**Debug**:
```bash
# Check MetalLB is running
kubectl get pods -n metallb-system

# Check MetalLB configuration
kubectl get ipaddresspools -n metallb-system -o yaml
kubectl get l2advertisements -n metallb-system -o yaml

# Check logs
kubectl logs -n metallb-system -l app=metallb,component=controller
kubectl logs -n metallb-system -l app=metallb,component=speaker

# Verify IP range is available
# Ping IPs in range from a machine on same network
ping 10.11.0.191
```

---

### Network Policy Blocks Legitimate Traffic

**Symptoms**: Connections fail after applying network policies

**Debug**:
```bash
# List all policies
kubectl get networkpolicies -A

# Check policy details
kubectl describe networkpolicy <policy-name>

# Temporarily delete policy to test
kubectl delete networkpolicy <policy-name>

# Check kube-router logs
kubectl logs -n kube-system -l k8s-app=kube-router | grep -i deny

# View generated iptables rules
sudo iptables -L KUBE-NWPLCY-<hash> -n -v
```

---

### DNS Resolution Fails

**Symptoms**: `nslookup` fails for services or external domains

**Debug**:
```bash
# Check CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test DNS from pod
kubectl run test-dns --image=busybox --rm -it -- sh
/ # nslookup kubernetes.default
/ # nslookup google.com
/ # cat /etc/resolv.conf

# Check DNS service
kubectl get svc -n kube-system kube-dns
```

---

## Advanced Topics

### Dual-Stack Networking (IPv4 + IPv6)

```yaml
k3s_enable_ipv6: true

extra_server_args: >-
  --cluster-cidr=10.42.0.0/16,fd00:42::/56
  --service-cidr=10.43.0.0/16,fd00:43::/112
  --flannel-backend=wireguard
  --flannel-iface={{ flannel_iface }}
```

### Multi-NIC Setup

For nodes with multiple network interfaces:

```yaml
# Use specific interface for different traffic
extra_server_args: >-
  --flannel-iface=eth1           # Internal pod network
  --bind-address=10.11.0.31      # Internal API server
  --advertise-address=146.165.244.31  # External API server
```

### Network Bandwidth Shaping

Limit pod network bandwidth:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bandwidth-limited-pod
  annotations:
    kubernetes.io/ingress-bandwidth: 10M
    kubernetes.io/egress-bandwidth: 10M
spec:
  containers:
  - name: app
    image: nginx
```

---

## See Also

- [Configuration Variables](configuration-variables.md)
- [Security Configuration](../SECURITY.md)
- [Storage Options](storage-options.md)
- [Troubleshooting Guide](troubleshooting.md)
