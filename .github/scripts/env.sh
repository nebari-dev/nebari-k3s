#!/usr/bin/env bash
set -euo pipefail

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

# Defaults (can be overridden by caller)
export NET="${NET:-192.168.56}"
export VIP="${VIP:-${NET}.10}"
export CPUS="${CPUS:-2}"
export MEM="${MEM:-4096}"

# Provider choice:
# - macOS: vagrant-qemu (QEMU native on Apple Silicon; no KVM) :contentReference[oaicite:2]{index=2}
# - Linux: vagrant-libvirt (QEMU/KVM) :contentReference[oaicite:3]{index=3}
if [[ "${OS}" == "darwin" ]]; then
  export VAGRANT_DEFAULT_PROVIDER="${VAGRANT_DEFAULT_PROVIDER:-qemu}"
  export PROVIDER="${PROVIDER:-qemu}"

  # Apple Silicon expects aarch64 images
  export ROCKY_BOX_URL="${ROCKY_BOX_URL:-https://download.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-Vagrant-Libvirt.latest.aarch64.box}" # :contentReference[oaicite:4]{index=4}
  export ROCKY_BOX_NAME="${ROCKY_BOX_NAME:-rocky9-aarch64-libvirt}"

else
  export VAGRANT_DEFAULT_PROVIDER="${VAGRANT_DEFAULT_PROVIDER:-libvirt}"
  export PROVIDER="${PROVIDER:-libvirt}"

  # Linux host arch decides which Rocky box
  if [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
    export ROCKY_BOX_URL="${ROCKY_BOX_URL:-https://download.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-Vagrant-Libvirt.latest.aarch64.box}" # :contentReference[oaicite:5]{index=5}
    export ROCKY_BOX_NAME="${ROCKY_BOX_NAME:-rocky9-aarch64-libvirt}"
  else
    export ROCKY_BOX_URL="${ROCKY_BOX_URL:-https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-Vagrant-Libvirt.latest.x86_64.box}" # :contentReference[oaicite:6]{index=6}
    export ROCKY_BOX_NAME="${ROCKY_BOX_NAME:-rocky9-x86_64-libvirt}"
  fi
fi

echo "Detected OS=${OS} ARCH=${ARCH}"
echo "PROVIDER=${PROVIDER} VAGRANT_DEFAULT_PROVIDER=${VAGRANT_DEFAULT_PROVIDER}"
echo "ROCKY_BOX_NAME=${ROCKY_BOX_NAME}"
echo "ROCKY_BOX_URL=${ROCKY_BOX_URL}"
