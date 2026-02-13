# K3s Storage Options

This document explains storage configuration options for K3s and how to integrate with various storage backends.

## Table of Contents

- [Default K3s Storage](#default-k3s-storage)
- [Local Path Provisioner](#local-path-provisioner)
- [Longhorn](#longhorn)
- [NFS Storage](#nfs-storage)
- [Rook-Ceph](#rook-ceph)
- [Migration Strategies](#migration-strategies)



## Default K3s Storage

K3s includes a built-in **Local Path Provisioner** as the default storage class.

### Overview

**Storage Class**: `local-path` **Provisioner**: `rancher.io/local-path` **Path**: `/var/lib/rancher/k3s/storage/`
**Reclaim Policy**: Delete **Volume Binding Mode**: WaitForFirstConsumer

### Characteristics

✅ **Pros**:
- Zero configuration required
- Fast local disk performance
- No additional components
- Works immediately after cluster creation

❌ **Cons**:
- Not replicated (data loss if node fails)
- Pod bound to specific node
- No data migration between nodes
- Limited to single-node access (ReadWriteOnce only)

### Viewing Default StorageClass

```bash
kubectl get storageclass
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

### Using Default Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

### Configuration Location

The local path provisioner configuration is stored in a ConfigMap:

```bash
kubectl get configmap -n kube-system local-path-config -o yaml
```

### Customizing Local Path

To change the storage path, edit the ConfigMap:

```bash
kubectl edit configmap -n kube-system local-path-config
```

Change the `config.json` section:
```json
{
  "nodePathMap":[
    {
      "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES",
      "paths":["/mnt/storage"]
    }
  ]
}
```

Then restart the local-path-provisioner:
```bash
kubectl rollout restart deployment -n kube-system local-path-provisioner
```



## Local Path Provisioner

For more control over local storage, you can deploy the standalone Local Path Provisioner.

### Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
```

### Custom Configuration

Create a ConfigMap for custom paths:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |-
    {
      "nodePathMap":[
        {
          "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES",
          "paths":["/mnt/disks/ssd1","/mnt/disks/ssd2"]
        },
        {
          "node":"node-01",
          "paths":["/mnt/nvme0"]
        },
        {
          "node":"node-02",
          "paths":["/mnt/nvme0"]
        }
      ]
    }
  setup: |-
    #!/bin/sh
    while getopts "m:s:p:" opt
    do
        case $opt in
            p)
            absolutePath=$OPTARG
            ;;
            s)
            sizeInBytes=$OPTARG
            ;;
            m)
            volMode=$OPTARG
            ;;
        esac
    done
    mkdir -m 0777 -p ${absolutePath}
  teardown: |-
    #!/bin/sh
    while getopts "m:s:p:" opt
    do
        case $opt in
            p)
            absolutePath=$OPTARG
            ;;
            s)
            sizeInBytes=$OPTARG
            ;;
            m)
            volMode=$OPTARG
            ;;
        esac
    done
    rm -rf ${absolutePath}
```

### Multiple StorageClasses

Create different StorageClasses for different performance tiers:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  nodePath: /mnt/fast-nvme
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: bulk-local
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
parameters:
  nodePath: /mnt/bulk-hdd
```



## Longhorn

Longhorn is a cloud-native distributed block storage solution for Kubernetes.

### Features

✅ **Advantages**:
- Replicated storage across nodes
- Automatic backups
- Disaster recovery
- Volume snapshots
- Cross-node pod migration
- ReadWriteMany support

### Prerequisites

```bash
# Install open-iscsi on all nodes (RedHat/Rocky)
ansible all -i hosts.ini -m shell -a "dnf install -y iscsi-initiator-utils"

# Enable and start iscsid
ansible all -i hosts.ini -m shell -a "systemctl enable --now iscsid"

# Verify kernel modules
ansible all -i hosts.ini -m shell -a "lsmod | grep iscsi"
```

### Installation via Helm

```bash
# Add Longhorn Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Create namespace
kubectl create namespace longhorn-system

# Install Longhorn
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --set defaultSettings.defaultReplicaCount=3 \
  --set persistence.defaultClass=true \
  --set persistence.defaultClassReplicaCount=3
```

### Installation via Ansible

Add to your playbook:

```yaml
- name: Install Longhorn
  hosts: master[0]
  become: no
  tasks:
    - name: Add Longhorn Helm repository
      kubernetes.core.helm_repository:
        name: longhorn
        repo_url: https://charts.longhorn.io

    - name: Install Longhorn
      kubernetes.core.helm:
        name: longhorn
        chart_ref: longhorn/longhorn
        release_namespace: longhorn-system
        create_namespace: true
        values:
          defaultSettings:
            defaultReplicaCount: 3
            defaultDataPath: /var/lib/longhorn
          persistence:
            defaultClass: true
            defaultClassReplicaCount: 3
```

### Configure Storage Path

To use custom storage paths, configure via values:

```yaml
# longhorn-values.yaml
defaultSettings:
  defaultDataPath: /mnt/longhorn  # Custom storage path
  defaultReplicaCount: 3

persistence:
  defaultClass: true
  defaultFsType: ext4
```

Apply:
```bash
helm upgrade longhorn longhorn/longhorn \
  --namespace longhorn-system \
  -f longhorn-values.yaml
```

### Accessing UI

```bash
# Create port-forward
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Or expose via Ingress
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
spec:
  rules:
  - host: longhorn.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: longhorn-frontend
            port:
              number: 80
EOF
```

### StorageClass Configuration

Longhorn automatically creates a StorageClass. To customize:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
  dataLocality: "best-effort"  # Keep data local when possible
```

### Backup Configuration

Configure S3 backup target:

```bash
# Via kubectl
kubectl edit settings.longhorn.io -n longhorn-system backup-target

# Set to:
# s3://my-bucket@us-east-1/backups
# with AWS credentials secret
```

Or via Helm values:
```yaml
defaultSettings:
  backupTarget: "s3://my-bucket@us-east-1/backups"
  backupTargetCredentialSecret: "longhorn-s3-secret"
```



## NFS Storage

Use NFS for shared storage across multiple pods (ReadWriteMany).

### Prerequisites

**NFS Server Setup** (on separate server or node):

```bash
# Install NFS server (Rocky Linux)
sudo dnf install -y nfs-utils

# Create export directory
sudo mkdir -p /export/k8s-storage
sudo chmod 777 /export/k8s-storage

# Configure exports
echo "/export/k8s-storage *(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports

# Start NFS server
sudo systemctl enable --now nfs-server

# Export shares
sudo exportfs -ra

# Check exports
sudo exportfs -v
```

**Firewall Configuration**:

```bash
# Allow NFS traffic
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload
```

### NFS Client Provisioner

Install the NFS Subdir External Provisioner:

```bash
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm install nfs-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=10.11.0.50 \
  --set nfs.path=/export/k8s-storage \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=false
```

### Manual NFS PV/PVC

Without provisioner, create manual PV/PVC:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 10.11.0.50
    path: "/export/k8s-storage/data"
  persistentVolumeReclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 100Gi
  volumeName: nfs-pv
```

### NFS Configuration in Ansible

Add NFS client setup to nodes:

```yaml
# roles/common/tasks/main.yaml
- name: Install NFS client packages
  ansible.builtin.package:
    name: nfs-utils
    state: present
  when: ansible_os_family == "RedHat"

- name: Ensure NFS services are enabled
  ansible.builtin.service:
    name: "{{ item }}"
    state: started
    enabled: true
  loop:
    - rpcbind
    - nfs-client.target
  when: ansible_os_family == "RedHat"
```



## Rook-Ceph

Rook-Ceph provides distributed block, object, and file storage.

### Prerequisites

- 3+ nodes recommended
- Raw block devices (unformatted disks) on each node
- At least 10GB per disk

### Installation

```bash
# Clone Rook repository
git clone --single-branch --branch v1.13.0 https://github.com/rook/rook.git
cd rook/deploy/examples

# Install Rook operator
kubectl create -f crds.yaml
kubectl create -f common.yaml
kubectl create -f operator.yaml

# Verify operator is running
kubectl get pods -n rook-ceph

# Create Ceph cluster
kubectl create -f cluster.yaml
```

### Minimal Cluster Configuration

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  dataDirHostPath: /var/lib/rook
  mon:
    count: 3
    allowMultiplePerNode: false
  storage:
    useAllNodes: true
    useAllDevices: true
    deviceFilter: "^sd[b-z]"  # Use sdb, sdc, etc.
```

### StorageClass for Block Storage

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
```

### CephFS for Shared Storage

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: myfs
  pool: myfs-data0
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
```



## Migration Strategies

### Migrating from local-path to Longhorn

1. **Install Longhorn** (see above)

2. **Create test PVC with Longhorn**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-longhorn-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

3. **For existing data, use rsync or backup/restore**:

```bash
# Example: Migrate data from pod using local-path to Longhorn

# 1. Scale down application
kubectl scale deployment my-app --replicas=0

# 2. Create temp pod with both PVCs
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: migration-pod
spec:
  containers:
  - name: migrator
    image: alpine:latest
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: old-data
      mountPath: /old
    - name: new-data
      mountPath: /new
  volumes:
  - name: old-data
    persistentVolumeClaim:
      claimName: old-local-pvc
  - name: new-data
    persistentVolumeClaim:
      claimName: new-longhorn-pvc
EOF

# 3. Copy data
kubectl exec migration-pod -- sh -c "cp -a /old/. /new/"

# 4. Update deployment to use new PVC
kubectl patch deployment my-app -p '{"spec":{"template":{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"new-longhorn-pvc"}}]}}}}'

# 5. Scale up application
kubectl scale deployment my-app --replicas=1

# 6. Verify and cleanup
kubectl delete pod migration-pod
kubectl delete pvc old-local-pvc
```

### Changing Default StorageClass

```bash
# Remove default from local-path
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Set new default (e.g., Longhorn)
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass
```



## Storage Comparison

| Solution | Type | Replication | Access Modes | Performance | Complexity | Use Case |
|----------|------|-------------|--------------|-------------|------------|----------|
| local-path | Local | ❌ No | RWO | ⭐⭐⭐⭐⭐ Fast | ⭐ Simple | Development, stateless |
| Longhorn | Distributed Block | ✅ Yes | RWO, RWX | ⭐⭐⭐⭐ Good | ⭐⭐ Moderate | General purpose |
| NFS | Network File | Depends on NFS | RWO, ROX, RWX | ⭐⭐⭐ Moderate | ⭐⭐ Moderate | Shared data |
| Rook-Ceph | Distributed Block/File/Object | ✅ Yes | RWO, RWX, ROX | ⭐⭐⭐⭐ Good | ⭐⭐⭐⭐ Complex | Enterprise |
| Cloud (EBS/PD) | Cloud Block | ✅ Cloud-managed | RWO | ⭐⭐⭐⭐ Good | ⭐⭐ Moderate | Cloud deployments |



## Best Practices

1. **Development**: Use local-path for speed and simplicity
2. **Production**: Use replicated storage (Longhorn, Ceph, or cloud)
3. **Shared Data**: Use NFS or CephFS (RWX support)
4. **Backups**: Always configure backups regardless of storage type
5. **Testing**: Test storage failure scenarios before production
6. **Monitoring**: Monitor storage capacity and performance



## See Also

- [Configuration Variables](configuration-variables.md)
- [High Availability Setup](high-availability.md)
- [Backup and Restore](backup-restore.md)
