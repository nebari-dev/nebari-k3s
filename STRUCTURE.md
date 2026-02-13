# Repository Structure

Clean Ansible best-practices layout for easy development and maintenance.

## Directory Layout

```
nebari-k3s/
├── playbooks/              # All Ansible playbooks
│   ├── site.yaml          # Main deployment playbook
│   ├── connectivity-check.yaml
│   ├── security-hardening.yaml
│   └── README.md
│
├── roles/                  # Ansible roles
│   ├── common/
│   ├── connectivity_check/
│   ├── k3s_master/
│   ├── k3s_worker/
│   ├── post_master/
│   ├── security_hardening/
│   └── [each with defaults/, tasks/, handlers/, README.md]
│
├── inventory/              # Inventory and variables
│   ├── production.ini     # Production inventory (customize this)
│   ├── group_vars/        # Group variables
│   │   └── all.yaml      # Variables for all hosts
│   ├── host_vars/         # Host-specific variables
│   ├── examples/          # Example inventory files
│   │   ├── production.ini.example
│   │   └── staging.ini.example
│   └── README.md
│
├── scripts/                # Operational scripts
│   ├── dry-run.sh         # Preview changes before applying
│   ├── kubeconfig_sync.sh # Sync kubeconfig from cluster
│   ├── test-security-hardening.sh
│   └── validate-security.sh
│
├── tests/                  # All tests (by type)
│   ├── integration/       # Integration tests
│   │   ├── vagrant/      # Local Vagrant test cluster
│   │   ├── security/     # Security validation suite
│   │   └── rocky9/       # Rocky Linux configs
│   └── README.md
│
├── docs/                   # Documentation
│   ├── README.md          # Documentation index
│   ├── operational-guide.md
│   ├── security-hardening.md
│   ├── configuration-variables.md
│   ├── network-configuration.md
│   └── [other guides]
│
├── .github/                # CI/CD
│   ├── workflows/         # GitHub Actions workflows
│   │   ├── vagrant-ha-security.yml
│   │   ├── security-scan.yml
│   │   └── test-operational-tools.yml
│   └── scripts/           # CI-specific scripts
│
├── archive/                # Archived content
│   └── benchmarks/        # Security benchmark configs
│
└── [root files]
    ├── ansible.cfg        # Ansible configuration (roles path, defaults)
    ├── README.md          # Project overview (you are here via link)
    ├── STRUCTURE.md       # This file
    ├── LICENSE
    ├── Makefile
    └── .gitignore
```

## Quick Navigation

> **Note:** All commands should be run from the repository root. The `ansible.cfg` file ensures Ansible finds roles,
> inventory, and uses appropriate defaults automatically.

### Common Tasks

| Task | Command | Documentation |
|------|---------|---------------|
| **Deploy cluster** | `ansible-playbook -i inventory/production.ini playbooks/site.yaml` | [playbooks/README.md](playbooks/README.md) |
| **Check connectivity** | `ansible-playbook -i inventory/production.ini playbooks/connectivity-check.yaml` | [docs/operational-guide.md](docs/operational-guide.md#connectivity-check) |
| **Preview changes** | `./scripts/dry-run.sh -i inventory/production.ini` | [docs/operational-guide.md](docs/operational-guide.md#dry-run-mode) |
| **Harden security** | `ansible-playbook -i inventory/production.ini playbooks/security-hardening.yaml` | [docs/security-hardening.md](docs/security-hardening.md) |
| **Run tests locally** | `cd tests/integration/vagrant && vagrant up` | [tests/README.md](tests/README.md) |

### Configuration

| What | Where | Documentation |
|------|-------|---------------|
| **Host inventory** | `inventory/production.ini` | [inventory/README.md](inventory/README.md) |
| **Cluster variables** | `inventory/group_vars/all.yaml` | [docs/configuration-variables.md](docs/configuration-variables.md) |
| **Per-host config** | `inventory/host_vars/<host>.yaml` | [inventory/README.md](inventory/README.md#host-variables) |
| **Role defaults** | `roles/<role>/defaults/main.yaml` | Each role's README.md |

### Development

| What | Where | Documentation |
|------|-------|---------------|
| **Create playbook** | `playbooks/my-playbook.yaml` | [playbooks/README.md](playbooks/README.md#playbook-development) |
| **Create role** | `roles/my-role/` | [Ansible Role Structure](https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html) |
| **Add test** | `tests/integration/my-test/` | [tests/README.md](tests/README.md#test-development) |
| **CI workflows** | `.github/workflows/` | [tests/README.md](tests/README.md#cicd-integration) |

## Design Principles

This structure follows:

1. **Standard Ansible Layout** - Familiar structure for Ansible users
2. **Separation of Concerns** - Clear boundaries between playbooks, roles, inventory, tests
3. **Easy Navigation** - Comprehensive README files at each level
4. **Scalable** - Works for both small and large deployments
5. **CI-Friendly** - Clear test organization for automated runs

## Migration from Old Structure

### Old → New Paths

| Old Path | New Path | Notes |
|----------|----------|-------|
| `playbook.yaml` | `playbooks/site.yaml` | Main playbook |
| `connectivity-check.yaml` | `playbooks/connectivity-check.yaml` | Moved |
| `security-hardening.yaml` | `playbooks/security-hardening.yaml` | Moved |
| `group_vars/` | `inventory/group_vars/` | Inventory vars |
| `group_vars/hosts.ini` | `inventory/production.ini` | Renamed |
| `tests/vagrant/` | `tests/integration/vagrant/` | Organized by type |
| `tests/security-suite/` | `tests/integration/security/` | Organized by type |
| `cfg/` | `archive/benchmarks/` | Archived |

### Update Your Commands

```bash
# Before
ansible-playbook -i hosts.ini playbook.yaml

# After
ansible-playbook -i inventory/production.ini playbooks/site.yaml
```

```bash
# Before
./scripts/dry-run.sh -i hosts.ini

# After
./scripts/dry-run.sh -i inventory/production.ini
```

```bash
# Before
cd tests/vagrant && vagrant up

# After
cd tests/integration/vagrant && vagrant up
```

## File Organization Conventions

### Playbooks (`playbooks/`)

- **One playbook per task** - site.yaml, connectivity-check.yaml, etc.
- **Clear naming** - Descriptive names that explain purpose
- **Documentation** - README.md with all playbooks documented

### Roles (`roles/`)

Standard Ansible role structure:
```
roles/my_role/
├── defaults/      # Default variables (lowest precedence)
├── tasks/         # Main tasks (required)
├── handlers/      # Event handlers
├── templates/     # Jinja2 templates
├── files/         # Static files
├── vars/          # Role variables (higher precedence)
└── README.md      # Role documentation
```

### Inventory (`inventory/`)

- **Environment-specific** - production.ini, staging.ini
- **Group variables** - group_vars/all.yaml, group_vars/k3s_master.yaml
- **Host variables** - host_vars/host1.yaml
- **Examples** - examples/ directory with .example files

### Tests (`tests/`)

- **By type** - integration/, e2e/ (when added)
- **Self-contained** - Each test suite has its own directory
- **Documented** - README.md at each level

## See Also

- **Main README**: [README.md](README.md) - Project overview
- **Playbooks**: [playbooks/README.md](playbooks/README.md) - Available playbooks
- **Inventory**: [inventory/README.md](inventory/README.md) - Inventory configuration
- **Tests**: [tests/README.md](tests/README.md) - Testing guide
- **Documentation**: [docs/README.md](docs/README.md) - All documentation

## Getting Help

1. **Check README files** - Start with directory-specific README.md
2. **Read documentation** - See [docs/](docs/)
3. **Review examples** - See [inventory/examples/](inventory/examples/)
4. **Run tests** - See [tests/](tests/)
5. **Open an issue** - GitHub issues for questions/bugs
