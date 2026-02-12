# macOS Testing Guide for nebari-k3s

**TL;DR**: Vagrant+QEMU doesn't work reliably on macOS. Use cloud VMs or skip local testing.

## ⚠️ The Problem

Vagrant with QEMU on macOS (especially Apple Silicon) has these issues:
- SSH connection hangs during boot
- No private network support
- Poor box compatibility
- **Setting up 5 local VMs is too resource-heavy anyway**

## 🎯 Practical Solutions

### Option 1: Cloud VMs (Recommended ⭐)

Use cloud VMs for testing - faster than local VMs and matches production:

```bash
# DigitalOcean, AWS, Hetzner, Linode, etc.
# Create 5 Rocky Linux 9 VMs (takes 5 minutes)
# Cost: ~$0.01-0.05/hour per VM = $1-5 for testing

# Then from your Mac:
ansible-playbook -i inventory/cloud.ini connectivity-check.yaml
./scripts/dry-run.sh -i inventory/cloud.ini
ansible-playbook -i inventory/cloud.ini playbook.yaml
```

**Pros**: Fast setup, realistic, no local resources **Cons**: Costs a few dollars

### Option 2: Single Test VM (Quick Testing)

Test roles on ONE VM instead of five:

```bash
# Create 1 cloud VM

# Test specific roles
ansible-playbook -i single-vm.ini playbook.yaml --tags common
ansible-playbook -i single-vm.ini playbook.yaml --tags firewall

# Much faster iteration
```

### Option 3: Docker Container (Syntax Checking)

Quick validation without VMs:

```bash
docker run -d --name test-node --privileged rockylinux:9 /sbin/init

# Test basic tasks (limited networking/firewall tests)
ansible-playbook -i docker-inventory.ini playbook.yaml --tags common

docker rm -f test-node
```

### Option 4: GitHub Actions CI (Zero Setup)

Let CI test on Linux for you:

```bash
git push
# Check: https://github.com/nebari-dev/nebari-k3s/actions
```

### Option 5: Direct to Staging (When you have infrastructure)

Skip local testing entirely:

```bash
# Validate syntax first (no VMs needed!)
./scripts/dry-run.sh -i inventory/staging.ini

# Apply on staging
ansible-playbook -i inventory/staging.ini playbook.yaml
```

## 📊 Quick Comparison

| Method | Setup | Cost | Best For |
|--------|-------|------|----------|
| **Cloud VMs** | 5 min | $1-5 | Full testing |
| **Single VM** | 2 min | $0.50 | Quick iteration |
| **Docker** | 1 min | Free | Syntax only |
| **GitHub CI** | 0 min | Free | Automated testing |
| **Direct staging** | 0 min | Free | Have staging env |

## 🎯 Recommended Workflow

```bash
# 1. Check syntax (no VMs needed!)
./scripts/dry-run.sh -i inventory/staging.ini

# 2. Test on cheap cloud VM
# Create 1-5 VMs based on what you're testing

# 3. Deploy with confidence
ansible-playbook -i inventory/production.ini playbook.yaml
```

## 🐛 Still Want Local Vagrant?

### Intel Mac: Use VirtualBox
```bash
brew install --cask virtualbox
cd tests/vagrant
vagrant up  # Auto-detects VirtualBox
```

### Apple Silicon: Not recommended
- vagrant-qemu hangs (as you experienced)
- No reliable solution
- **Use cloud VMs instead**

### Kill stuck Vagrant
```bash
vagrant destroy -f
pkill -f qemu
```

## 💡 Example: Quick DigitalOcean Setup

```bash
# Install CLI
brew install doctl
doctl auth init

# Create 5 test nodes (takes 2-3 minutes)
for i in 1 2 3 4 5; do
  doctl compute droplet create test-$i \
    --image rockylinux-9-x64 \
    --size s-2vcpu-4gb \
    --region nyc1 \
    --ssh-keys YOUR_KEY_ID
done

# Get IPs
doctl compute droplet list

# Create inventory and test!
ansible-playbook -i inventory/do.ini playbook.yaml

# Destroy when done (stop the billing)
doctl compute droplet delete test-1 test-2 test-3 test-4 test-5
```

**Total cost**: ~$0.25 for an hour of testing

## ✅ Bottom Line

**Don't fight with Vagrant on macOS.**

Better workflow:
1. Edit code on macOS
2. Run `./scripts/dry-run.sh` for syntax
3. Test on 1-5 cheap cloud VMs
4. Deploy to production

**Time saved**: Hours of debugging **Cost**: $1-5 for thorough testing



**The goal is testing k3s deployments, not making Vagrant work. Use what works!**
