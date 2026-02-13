# Tests

Integration and end-to-end tests for nebari-k3s.

## Structure

```
tests/
├── integration/          # Integration tests
│   ├── vagrant/         # Vagrant-based local testing
│   ├── security/        # Security validation suite
│   └── rocky9/          # Rocky Linux 9 test environment
└── README.md            # This file
```

## Quick Start

### Integration Tests with Vagrant

```bash
# Start test cluster
cd integration/vagrant
vagrant up

# Run playbooks against test cluster
ansible-playbook -i hosts.ini ../../playbooks/site.yaml

# Run security tests
cd ../security
./run-security-tests.sh --inventory ../vagrant/hosts.ini
```

### CI/CD Testing

Tests are automatically run in GitHub Actions:

- **vagrant-ha-security.yml** - 3-node HA cluster with security validation
- **security-scan.yml** - Trivy + kubescape security scanning
- **test-operational-tools.yml** - Dry-run and connectivity check validation

## Integration Tests

### [integration/vagrant/](integration/vagrant/)

**Local development cluster using Vagrant + libvirt/VirtualBox**

**Features:**
- 3-node K3s cluster (1 control plane, 2 workers)
- Rocky Linux 9 or Ubuntu
- Minimal resource usage (2GB RAM per VM)
- Full playbook testing

**Usage:**
```bash
cd integration/vagrant
vagrant up
ansible-playbook -i hosts.ini ../../playbooks/site.yaml
vagrant destroy
```

**See:** [integration/vagrant/README.md](integration/vagrant/README.md)

---

### [integration/security/](integration/security/)

**Comprehensive security validation suite**

**Tests:**
1. Port exposure validation
2. Firewall configuration checks
3. Network segmentation validation
4. Compliance checks (CIS benchmarks)
5. K3s-specific security

**Usage:**
```bash
cd integration/security
./run-security-tests.sh --inventory ../vagrant/hosts.ini --output-dir reports/
```

**See:** [integration/security/README.md](integration/security/README.md)

---

### [integration/rocky9/](integration/rocky9/)

**Rocky Linux 9 specific test configuration**

Contains environment-specific configurations and test data for Rocky Linux 9.

---

## Running Tests

### Full Integration Test

```bash
# 1. Start Vagrant cluster
cd tests/integration/vagrant
vagrant up

# 2. Deploy cluster
ansible-playbook -i hosts.ini ../../playbooks/site.yaml

# 3. Run security tests
cd ../security
./run-security-tests.sh --inventory ../vagrant/hosts.ini

# 4. Cleanup
cd ../vagrant
vagrant destroy -f
```

### Specific Test Suites

```bash
# Only connectivity check
ansible-playbook -i tests/integration/vagrant/hosts.ini \
  playbooks/connectivity-check.yaml

# Only security hardening
ansible-playbook -i tests/integration/vagrant/hosts.ini \
  playbooks/security-hardening.yaml

# Specific security test
cd tests/integration/security
./tests/01-port-exposure.sh ../vagrant/hosts.ini
```

### CI Simulation

```bash
# Run same tests as CI locally
cd tests/integration/vagrant
vagrant up

# Run security scan (like CI)
cd ../security
./run-security-tests.sh \
  --inventory ../vagrant/hosts.ini \
  --output-dir ../../reports/vagrant \
  --quick \
  --verbose
```

## Test Development

### Adding a New Integration Test

1. **Create test directory:**
   ```bash
   mkdir -p tests/integration/my-test
   ```

2. **Add test script:**
   ```bash
   #!/bin/bash
   # tests/integration/my-test/test.sh
   
   set -euo pipefail
   
   INVENTORY=${1:-hosts.ini}
   
   echo "Running my test..."
   ansible -i "$INVENTORY" all -m ping
   # ... test logic
   ```

3. **Make it executable:**
   ```bash
   chmod +x tests/integration/my-test/test.sh
   ```

4. **Add to CI if needed:**
   Edit `.github/workflows/` to include your test.

### Test Best Practices

1. **Always cleanup** - Use traps or finally blocks
2. **Idempotent** - Tests should be repeatable
3. **Fast feedback** - Fail fast on errors
4. **Clear output** - Use colors and clear messages
5. **Document** - README.md for each test suite

### Example Test Script

```bash
#!/bin/bash
# tests/integration/example/test-example.sh
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Configuration
INVENTORY=${1:-../vagrant/hosts.ini}
PASSED=0
FAILED=0

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

# Tests
echo "Running example tests..."

# Test 1: Connectivity
if ansible -i "$INVENTORY" all -m ping >/dev/null 2>&1; then
    pass "All nodes reachable"
else
    fail "Some nodes unreachable"
fi

# Test 2: K3s running
if ansible -i "$INVENTORY" all -b -m systemd \
    -a "name=k3s state=started" >/dev/null 2>&1; then
    pass "K3s service running"
else
    fail "K3s service not running"
fi

# Summary
echo ""
echo "Passed: $PASSED"
echo "Failed: $FAILED"
[ $FAILED -eq 0 ] && exit 0 || exit 1
```

## CI/CD Integration

### GitHub Actions Workflows

Located in `.github/workflows/`:

1. **vagrant-ha-security.yml**
   - 3-node HA cluster
   - Full playbook execution
   - Security validation
   - Runs on: push to non-main branches

2. **security-scan.yml**
   - Trivy vulnerability scanning
   - kubescape CIS benchmark
   - Security test suite
   - Runs on: pull requests

3. **test-operational-tools.yml**
   - Dry-run mode validation
   - Connectivity check validation
   - Runs on: changes to scripts/

### Adding Tests to CI

Edit `.github/workflows/*.yml`:

```yaml
- name: Run my test
  run: |
    cd tests/integration/my-test
    ./test.sh ../vagrant/hosts.ini
```

## Troubleshooting

### Vagrant Issues

```bash
# Destroy and start fresh
vagrant destroy -f
vagrant up

# Check VM status
vagrant status
virsh list --all  # For libvirt

# SSH into VM
vagrant ssh cp1
```

### Ansible Issues

```bash
# Verbose output
ansible-playbook -i hosts.ini playbooks/site.yaml -vvv

# Check inventory
ansible-inventory -i hosts.ini --list

# Test connection
ansible -i hosts.ini all -m ping -vvv
```

### Test Failures

```bash
# Run single test with verbose
bash -x tests/integration/security/tests/01-port-exposure.sh

# Check logs
vagrant ssh cp1 -c "sudo journalctl -u k3s -n 100"

# Check iptables
vagrant ssh cp1 -c "sudo iptables -t raw -L PREROUTING -n -v"
```

## Performance

### Test Duration

- **Vagrant up**: ~5-8 minutes
- **Ansible playbook**: ~3-5 minutes
- **Security suite**: ~5-10 minutes
- **Total**: ~15-20 minutes

### Optimization Tips

1. **Parallel execution** - Use `--forks` flag
2. **Cached boxes** - Vagrant boxes are cached
3. **Incremental testing** - Use tags to test parts
4. **CI matrix** - Test environments in parallel

## See Also

- [../playbooks/](../playbooks/) - Playbooks being tested
- [../docs/operational-guide.md](../docs/operational-guide.md) - Operational procedures
- [integration/vagrant/README.md](integration/vagrant/README.md) - Vagrant testing
- [integration/security/README.md](integration/security/README.md) - Security tests
- [../.github/workflows/](../.github/workflows/) - CI configuration
