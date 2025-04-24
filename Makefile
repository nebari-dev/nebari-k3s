.PHONY: all kubeconfig-sync

all: kubeconfig-sync

kubeconfig-sync:
	./scripts/kubeconfig_sync.sh sync
	@echo "Kubeconfig synchronized."
	@echo "You can now use kubectl commands with the synchronized kubeconfig."
	@echo "For example, run 'kubectl get nodes -o wide' to verify the synchronization."
