#!/usr/bin/env bash
set -euo pipefail

# ——————————————————————————————————————————————
# Load & validate environment
# Required env vars:
#   SSH_USER     (default: root)
#   SSH_HOST     (required)
#   SSH_PORT     (default: 22)
#   SSH_KEY_FILE (required)
#   REMOTE_PATH  (default: ~/.kube/config)

SSH_USER="${SSH_USER:-root}"
SSH_HOST="${SSH_HOST:?SSH_HOST must be set}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_FILE="${SSH_KEY_FILE:?SSH_KEY_FILE must be set}"
REMOTE_PATH="${REMOTE_PATH:-~/.kube/config}"

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
  create_tmp_dir
  copy_kubeconfig
  merge_kubeconfigs
  backup_kubeconfig
  apply_merged_config
}

main() {
  case "${1:-}" in
    help|-h)
      echo "Usage: $0 {sync|help}"
      exit 0
      ;;
    sync)
      sync_all
      ;;
    *)
      echo "Usage: $0 {sync|help}"
      exit 1
      ;;
  esac
}

main "$1"
