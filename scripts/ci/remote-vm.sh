#!/usr/bin/env bash
set -euo pipefail

# Environment (exported by GH Actions)
# SSH_HOST, SSH_PORT, SSH_USER, SSH_KEY_FILE

# 1) Launch a throw-away “remote VM” container
docker run -d --name remote_vm \
  -p "${SSH_PORT}:22" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --privileged ubuntu:20.04 \
  bash -lc "\
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server curl && \
    mkdir /var/run/sshd && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo '${SSH_USER}:${SSH_USER}' | chpasswd && \
    service ssh start && \
    sleep infinity
  "

# 2) Copy your public key in
ssh -o StrictHostKeyChecking=no -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
   echo '$(< "${SSH_KEY_FILE}.pub")' >> ~/.ssh/authorized_keys && \
   chmod 600 ~/.ssh/authorized_keys"

# 3) Install kubectl & kind, then create a Kind cluster
ssh -o StrictHostKeyChecking=no -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" bash -lc "
  curl -Lo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.27.0/bin/linux/amd64/kubectl && \
  chmod +x /usr/local/bin/kubectl && \
  curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && \
  chmod +x /usr/local/bin/kind && \
  mkdir -p ~/kube && \
  kind create cluster --name ci-test --kubeconfig ~/kube/config
"
