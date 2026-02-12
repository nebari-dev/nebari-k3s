#!/usr/bin/env bash
set -euo pipefail

# This script launches a throw-away container, installs Docker CLI, kubectl & kind,
# and creates a test Kind cluster.

# 0) Remove any existing test container
docker rm -f remote_vm >/dev/null 2>&1 || true

# 1) Spin up a container with Docker socket mounted
docker run -d \
  --name remote_vm \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ubuntu:20.04 \
  tail -f /dev/null

# 2) Bootstrap inside the container:
#    install curl, docker CLI, kubectl, kind, then delete + create the cluster
docker exec -i remote_vm bash << 'EOF'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl docker.io
mkdir -p /root/.kube

# Install kubectl
curl -Lo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.27.0/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

# Install kind
curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x /usr/local/bin/kind

# Delete any existing Kind cluster named ci-test
docker info >/dev/null && kind delete cluster --name ci-test || true

# Create the Kind cluster
kind create cluster --name ci-test --kubeconfig /root/.kube/config
EOF
