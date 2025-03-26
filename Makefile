-include .env

# Variables (can be overridden by .env)
REMOTE_USER ?= youruser
REMOTE_HOST ?= your.remote.host
REMOTE_HOME ?= /home/$(REMOTE_USER)
SSH_KEY_FILE ?= ~/.ssh/id_rsa
TMP_DIR ?= /tmp/kubeconfig
LOCAL_KUBECONFIG ?= ~/.kube/config
REMOTE_KUBECONFIG ?= $(REMOTE_HOME)/.kube/config

# Targets
.PHONY: ssh-add backup copy merge apply clean all

ssh-add:
	@echo "Adding SSH key: $(SSH_KEY_FILE)..."
	ssh-add $(SSH_KEY_FILE)

$(TMP_DIR):
	mkdir -p $(TMP_DIR)

backup:
	@if [ -f $(LOCAL_KUBECONFIG) ]; then \
		BACKUP_FILE=$(LOCAL_KUBECONFIG).bak.$$(date '+%Y%m%d_%H%M%S'); \
		cp $(LOCAL_KUBECONFIG) $$BACKUP_FILE; \
		echo "Backup of existing kubeconfig created at $$BACKUP_FILE"; \
	else \
		echo "No existing kubeconfig found; skipping backup."; \
	fi

copy: $(TMP_DIR)
	@echo "Copying remote kubeconfig..."
	vagrant scp hpc-master-01:$(REMOTE_HOME)/.kube/config $(TMP_DIR)/remote.config

merge: backup copy
	@echo "Merging kubeconfig files..."
	KUBECONFIG=$(TMP_DIR)/remote.config:$(LOCAL_KUBECONFIG) \
		kubectl config view --raw --flatten > $(TMP_DIR)/final.config
	chmod 600 $(TMP_DIR)/final.config
	@echo "Merged kubeconfig is now at: $(TMP_DIR)/final.config"

apply: merge
	@echo "Replacing local kubeconfig with merged config..."
	mkdir -p $(HOME)/.kube
	mv $(TMP_DIR)/final.config $(LOCAL_KUBECONFIG)
	@echo "Local kubeconfig updated successfully."

clean:
	rm -rf $(TMP_DIR)

all: ssh-add apply
