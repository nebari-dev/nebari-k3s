#!/usr/bin/env bash
set -euo pipefail

if [ -f ./.env ]; then
  source ./.env
fi

# Required env vars:
# SSH_USER: user to SSH as (default: root)
# SSH_HOST: remote host to fetch kubeconfig from (required)
# SSH_PORT: SSH port (default: 22)
# SSH_KEY_FILE: path to private key for SSH (required)
# REMOTE_PATH: remote kubeconfig path (default: ~/.kube/config)

SSH_USER="${SSH_USER:-root}"
SSH_HOST="${SSH_HOST:?SSH_HOST must be set}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_FILE="${SSH_KEY_FILE:?SSH_KEY_FILE must be set}"
REMOTE_PATH="${REMOTE_PATH:-~/.kube/config}"

add_ssh_key() {
  echo "Adding SSH key: $SSH_KEY_FILE…"
  ssh-add "$SSH_KEY_FILE"
}

create_tmp_dir() {
  mkdir -p /tmp/kubeconfig
}

backup_kubeconfig() {
  if [ -f ~/.kube/config ]; then
    ts=$(date '+%Y%m%d_%H%M%S')
    cp ~/.kube/config ~/.kube/config.bak."$ts"
    echo "Backed up to ~/.kube/config.bak.$ts"
  else
    echo "No existing ~/.kube/config → skipping backup."
  fi
}

copy_kubeconfig() {
  echo "Copying remote kubeconfig from $SSH_USER@$SSH_HOST:$REMOTE_PATH…"
  mkdir -p /tmp/kubeconfig
  scp -i "$SSH_KEY_FILE" -P "$SSH_PORT" \
    "$SSH_USER@$SSH_HOST:$REMOTE_PATH" \
    /tmp/kubeconfig/remote.config
}

merge_kubeconfigs() {
  echo "Merging /tmp/kubeconfig/remote.config + ~/.kube/config → final.config"
  KUBECONFIG=/tmp/kubeconfig/remote.config:~/.kube/config \
    kubectl config view --raw --flatten \
      > /tmp/kubeconfig/final.config
  chmod 600 /tmp/kubeconfig/final.config
}

apply_merged_config() {
  echo "Installing merged config to ~/.kube/config"
  mkdir -p ~/.kube
  cp /tmp/kubeconfig/final.config ~/.kube/config
}

sync_all() {
  add_ssh_key
  create_tmp_dir
  copy_kubeconfig
  merge_kubeconfigs
  backup_kubeconfig
  apply_merged_config
}

# ---------------------------------------------------

main() {
  case "${1:-}" in
    help|-h)
      echo "Usage: $0 {ssh-add|sync|help}"
      exit 0
      ;;
    ssh-add)
      add_ssh_key
      ;;
    apply|sync)
      sync_all
      ;;
    *)
      echo "Usage: $0 {ssh-add|sync|help}"
      exit 1
      ;;
  esac
}

main "$1"
