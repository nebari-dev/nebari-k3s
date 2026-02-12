# Security Test Suite - NASA Compliance Validation

This test suite validates all security hardening implementations and generates compliance reports for NASA security standards.

## 🎯 Purpose

- **Validate security patches** - Ensure all firewall rules and network segmentation work correctly
- **Port exposure audit** - Confirm no sensitive ports (6443, 10250, 2379-2380, 30000-32767) are publicly accessible
- **Compliance reporting** - Generate detailed reports for security scan findings
- **Before/After comparison** - Compare old cluster vs. hardened cluster
- **Migration readiness** - Validate cluster is ready for production migration

## 📋 Test Coverage

### 1. Port Exposure Tests
- External port scanning from outside network
- Verify blocked ports (kubelet, etcd, NodePorts)
- Confirm allowed ports (SSH, HTTP/S, ingress)
- Admin-only API access validation

### 2. Firewall Configuration Tests
- Zone configuration (public, k3s-cluster, trusted)
- Rich rule validation
- Node-to-node communication
- Admin CIDR restrictions

### 3. Network Segmentation Tests
- Inter-node traffic isolation
- Service mesh connectivity
- Pod network functionality
- LoadBalancer/MetalLB operation

### 4. Security Compliance Tests
- CIS Kubernetes Benchmark checks
- NIST 800-53 controls
- NASA security requirements
- CVE scanning

### 5. K3s-Specific Tests
- Kubelet authentication
- API server TLS
- etcd encryption at rest
- Service account token security

## 🚀 Quick Start

### Prerequisites

```bash
# Install required tools
sudo dnf install -y nmap nc telnet curl jq git
pip3 install ansible pytest pyyaml

# Optional: Install security scanners
# kube-bench for CIS benchmarks
wget https://github.com/aquasecurity/kube-bench/releases/download/v0.7.1/kube-bench_0.7.1_linux_amd64.tar.gz
tar -xvf kube-bench_0.7.1_linux_amd64.tar.gz
sudo mv kube-bench /usr/local/bin/

# trivy for vulnerability scanning
wget https://github.com/aquasecurity/trivy/releases/download/v0.48.0/trivy_0.48.0_Linux-64bit.tar.gz
tar -xvf trivy_0.48.0_Linux-64bit.tar.gz
sudo mv trivy /usr/local/bin/
```

### Run Full Test Suite

```bash
cd tests/security-suite

# Test against Rocky9 vagrant lab
./run-security-tests.sh --inventory ../rocky9/hosts.ini --output-dir reports/

# Test against production cluster
./run-security-tests.sh --inventory ../../inventories/production.ini --output-dir reports/prod/

# Generate comparison report
./compare-clusters.sh reports/old-cluster.json reports/prod/security-report.json
```

### Run Individual Test Categories

```bash
# Port exposure tests only
./tests/01-port-exposure.sh ../rocky9/hosts.ini

# Firewall configuration tests
./tests/02-firewall-config.sh ../rocky9/hosts.ini

# Network segmentation tests
./tests/03-network-segmentation.sh ../rocky9/hosts.ini

# Compliance tests (CIS + NIST)
./tests/04-compliance.sh ../rocky9/hosts.ini

# K3s security tests
./tests/05-k3s-security.sh ../rocky9/hosts.ini
```

## 📊 Reports Generated

All reports are saved in JSON and HTML formats:

1. **`security-report.json`** - Complete test results in machine-readable format
2. **`security-report.html`** - Human-readable HTML report with charts
3. **`port-scan-results.txt`** - Detailed nmap scan output
4. **`compliance-summary.json`** - CIS/NIST compliance scoring
5. **`findings.csv`** - Security findings in CSV for tracking
6. **`comparison-report.html`** - Side-by-side before/after comparison

### Report Sections

Each report includes:
- **Executive Summary** - Pass/fail counts, compliance percentage
- **Critical Findings** - Issues requiring immediate attention
- **Port Exposure Matrix** - Which ports are accessible from where
- **Firewall Configuration** - Zone and rule validation results
- **Network Tests** - Connectivity and isolation validation
- **Compliance Scores** - CIS benchmark and NIST control compliance
- **Recommendations** - Actionable items to improve security
- **Evidence** - Command outputs and logs for audit trail

## 🔍 Test Details

### Port Exposure Tests (`01-port-exposure.sh`)

Tests external accessibility of all critical ports:

```bash
# Tests performed:
- nmap scan from external host (simulates attacker)
- Verify 6443 (API) only accessible from admin CIDRs
- Verify 10250 (kubelet) is blocked externally
- Verify 2379-2380 (etcd) is blocked externally
- Verify 30000-32767 (NodePorts) are blocked
- Verify 22 (SSH) only accessible from admin CIDRs
- Verify 80/443 (ingress) accessible based on config
```

**Expected Results:**
- ✅ API (6443) blocked from unauthorized IPs
- ✅ Kubelet (10250) not accessible externally
- ✅ etcd (2379-2380) not accessible externally
- ✅ NodePorts blocked unless explicitly allowed
- ✅ SSH restricted to admin CIDRs
- ✅ Ingress (80/443) open only if configured

### Firewall Configuration Tests (`02-firewall-config.sh`)

Validates firewalld zone configuration on all nodes:

```bash
# Tests performed:
- Verify k3s-cluster zone exists with DROP target
- Verify all node IPs in k3s-cluster zone sources
- Verify public zone has correct rich rules
- Verify admin CIDRs configured correctly
- Test zone priority order
- Validate persistent configuration
```

**Expected Results:**
- ✅ k3s-cluster zone configured with DROP default
- ✅ Node-to-node traffic uses k3s-cluster zone
- ✅ Public zone blocks sensitive ports
- ✅ Admin access restricted to configured CIDRs
- ✅ Configuration persists across reboots

### Network Segmentation Tests (`03-network-segmentation.sh`)

Tests inter-node and pod network functionality:

```bash
# Tests performed:
- Node-to-node communication on allowed ports
- Pod-to-pod communication across nodes
- Service discovery and DNS
- LoadBalancer/MetalLB functionality
- Ingress controller operation
- NetworkPolicy enforcement
```

**Expected Results:**
- ✅ Nodes communicate on required ports (6443, 8472, 10250 internally)
- ✅ Pods reach each other via CNI
- ✅ Services resolve correctly
- ✅ MetalLB assigns and responds on LoadBalancer IPs
- ✅ Ingress routes traffic properly
- ✅ NetworkPolicies block unauthorized traffic

### Compliance Tests (`04-compliance.sh`)

Runs CIS Kubernetes Benchmark and NIST controls:

```bash
# Tests performed:
- CIS Benchmark automated checks (kube-bench)
- NIST 800-53 control validation
- API server security settings
- RBAC configuration audit
- Pod Security Standards
- Network policy requirements
- Audit logging validation
```

**Expected Results:**
- ✅ CIS score ≥ 90% (Level 1 automated checks)
- ✅ NIST controls implemented: AC-4, SC-7, AU-2
- ✅ API server has secure flags
- ✅ RBAC limits cluster-admin usage
- ✅ Pod Security admission enabled
- ✅ Network policies applied
- ✅ Audit logs captured

### K3s Security Tests (`05-k3s-security.sh`)

K3s-specific security validations:

```bash
# Tests performed:
- Kubelet anonymous-auth disabled
- API server authentication mode
- etcd encryption configuration
- Service account issuer validation
- Secrets encryption at rest
- Container runtime security
```

**Expected Results:**
- ✅ Kubelet requires authentication
- ✅ API server uses certificates
- ✅ etcd data encrypted
- ✅ Service accounts use bound tokens
- ✅ Secrets encrypted in etcd
- ✅ containerd properly configured

## 🆚 Cluster Comparison

The comparison tool analyzes before/after state:

```bash
# Generate baseline from old cluster
./capture-baseline.sh OLD_CLUSTER_IP > reports/baseline-old.json

# Run tests on new cluster
./run-security-tests.sh --inventory ../rocky9/hosts.ini --output-dir reports/

# Compare
./compare-clusters.sh reports/baseline-old.json reports/security-report.json --html reports/migration-comparison.html
```

**Comparison Metrics:**
- Port exposure differences
- Security improvements
- New vulnerabilities (if any)
- Performance impact
- Configuration changes
- Compliance score delta

## 📝 NASA Compliance Checklist

This test suite validates the following NASA security requirements:

- [ ] **NPR 2810.1** - Information Security Program
  - [x] Network segmentation implemented
  - [x] Access controls enforced
  - [x] Audit logging enabled
  
- [ ] **NIST 800-53 Controls**
  - [x] AC-4: Information Flow Enforcement (firewall zones)
  - [x] SC-7: Boundary Protection (blocked ports)
  - [x] AU-2: Audit Events (K3s audit logs)
  - [x] CM-7: Least Functionality (disabled unnecessary services)
  
- [ ] **CIS Kubernetes Benchmark**
  - [x] Control Plane Security Configuration
  - [x] Worker Node Security Configuration
  - [x] Network Policies and CNI
  
- [ ] **Port Security**
  - [x] No unauthenticated API access (6443)
  - [x] No external kubelet access (10250)
  - [x] No external etcd access (2379-2380)
  - [x] No exposed NodePorts (30000-32767)

## 🔧 Customization

### Add Custom Tests

Create a new test file following the template:

```bash
#!/usr/bin/env bash
# tests/XX-custom-test.sh

set -euo pipefail

INVENTORY="${1:?Usage: $0 <inventory.ini>}"
source "$(dirname "$0")/../lib/test-helpers.sh"

test_description "My Custom Security Test"

# Your test logic here
run_test "Test case name" "command to run"

# Output results
output_results
```

### Configure Test Parameters

Edit `config/test-config.yaml`:

```yaml
scan_timeout: 300
retry_attempts: 3
parallel_scans: true
external_scanner_ip: "0.0.0.0"  # IP to scan from
admin_test_ip: "192.168.1.100"  # Admin IP for access tests
report_format: ["json", "html", "csv"]
```

## 🐛 Troubleshooting

### Tests Failing to Connect

```bash
# Verify SSH access
ansible all -i ../rocky9/hosts.ini -m ping

# Check firewall allows test traffic
sudo firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="TEST_IP/32" accept'
```

### False Positives

Some tests may show warnings that are acceptable:
- NodePort accessible from admin CIDR (expected if configured)
- Metrics ports (9100, 9090) open internally (acceptable)
- ICMP blocked (acceptable security posture)

Check `config/allowed-findings.yaml` to suppress known acceptable findings.

### Permission Issues

```bash
# Tests require sudo on target nodes
ansible all -i inventory.ini -m shell -a "sudo firewall-cmd --list-all" --become
```

## 📚 Additional Resources

- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST 800-53 Controls](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
- [NASA NPR 2810.1](https://nodis3.gsfc.nasa.gov/displayDir.cfm?t=NPR&c=2810&s=1)
- [K3s Security Best Practices](https://docs.k3s.io/security/hardening-guide)

## 🤝 Contributing

To add new test cases:
1. Create test script in `tests/`
2. Add to `run-security-tests.sh`
3. Update this README with test description
4. Add expected results to `config/expected-results.yaml`
