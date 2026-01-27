#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}/tests/rocky9"

source "${ROOT}/tests/bin/env.sh"

# Pre-add box (idempotent-ish)
vagrant box add --name "${ROCKY_BOX_NAME}" "${ROCKY_BOX_URL}" --provider=libvirt || true

vagrant up --provider="${PROVIDER}"

cd "${ROOT}"
ansible-playbook -i tests/rocky9/inventories/hosts.ini playbook.yaml

"${ROOT}/tests/bin/security-scan.sh" tests/rocky9/inventories/hosts.ini
