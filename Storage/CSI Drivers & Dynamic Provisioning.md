# CSI Drivers & Dynamic Provisioning

Container Storage Interface (CSI), Kubernetes'in depolama sistemleriyle konuşma standardıdır. 2019'dan itibaren tüm in-tree (kernel içi) storage plugin'leri CSI'a taşındı.

---

## CSI Nedir?

Kubernetes'in depolama yönetimini storage vendor'larından bağımsız hale getiren standart arayüz. Her storage sistemi (AWS EBS, Azure Disk, Longhorn, Rook/Ceph) kendi CSI driver'ını yazar; Kubernetes aynı API ile hepsini yönetir.

```
[Kubernetes]
     │
     ├── CSI Controller Plugin (Deployment — cluster'da bir tane)
     │     ├── CreateVolume / DeleteVolume
     │     ├── AttachVolume / DetachVolume
     │     └── CreateSnapshot / DeleteSnapshot
     │
     └── CSI Node Plugin (DaemonSet — her node'da)
           ├── NodePublishVolume (mount)
           └── NodeUnpublishVolume (unmount)
```

---

## Longhorn — Dağıtık Block Storage

Rancher tarafından geliştirilen, Kubernetes-native dağıtık storage çözümü. Her volume her node'a replike edilir.

### Kurulum

```bash
# Ön koşul: her node'da open-iscsi
apt install open-iscsi -y    # Ubuntu/Debian

# Helm ile kurulum
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=3 \
  --set defaultSettings.storageMinimalAvailablePercentage=15
```

### Longhorn StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"           # Her volume 3 node'da replike
  staleReplicaTimeout: "2880"     # 2 gün sonra stale replica temizle
  fromBackup: ""
  fsType: ext4
```

### Longhorn UI Erişimi

```bash
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80
# http://localhost:8080
```

---

## Rook/Ceph — Enterprise Dağıtık Storage

Büyük ölçekli, çoklu storage türü (Block, Filesystem, Object) desteği olan sistem.

### Kurulum

```bash
git clone --single-branch --branch v1.13.0 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl apply -f crds.yaml -f common.yaml -f operator.yaml
kubectl apply -f cluster.yaml       # Ceph cluster oluştur
```

### StorageClass'lar

```yaml
# Block Storage (RWO)
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
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete

---
# Shared Filesystem (RWX)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: myfs
  pool: myfs-replicated
allowVolumeExpansion: true
```

---

## NFS CSI Driver

Paylaşımlı (RWX) storage için en basit çözüm.

```bash
# NFS CSI driver kurulumu
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server.example.com
  share: /exports/data
  subDir: ${pvc.metadata.namespace}/${pvc.metadata.name}
reclaimPolicy: Retain
allowVolumeExpansion: true
mountOptions:
  - nfsvers=4.1
  - hard
  - timeo=600
```

---

## Cloud Provider CSI Drivers

### AWS EBS

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer   # AZ bazlı binding
```

### Azure Disk

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-premium
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS
  cachingMode: ReadOnly
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### GCP Persistent Disk

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcp-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: regional-pd    # Bölgesel replikasyon
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

---

## CSI Driver Durumu Kontrolü

```bash
# CSI driver pod'ları
kubectl get pods -A | grep -i "csi\|longhorn\|rook"

# CSIDriver objesi
kubectl get csidriver

# CSINode (her node'da driver kayıtlı mı?)
kubectl get csinode

# Volume attachment durumu
kubectl get volumeattachments

# StorageClass detayı
kubectl describe storageclass <sc-adı>
```

---

## Dynamic Provisioning Akışı

```
1. Kullanıcı PVC oluşturur
        │
2. Kubernetes StorageClass'ı bulur
        │
3. CSI Controller "CreateVolume" çağrısı yapar
   (cloud disk/longhorn volume oluşur)
        │
4. PV otomatik oluşturulur, PVC'ye Bound olur
        │
5. Pod schedule edildiğinde CSI Node "NodePublishVolume" çağrısı
   (disk node'a mount edilir)
        │
6. Container /data mount point'ini görür
```

---

## Volume Genişletme

```bash
# PVC kapasitesini artır (StorageClass allowVolumeExpansion: true olmalı)
kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Genişleme durumu
kubectl describe pvc my-pvc | grep -A5 "Conditions"
# "FileSystemResizePending" → Pod yeniden başlatılmalı

# Pod yeniden başlatılırsa otomatik resize olur
kubectl rollout restart deployment/<dep>
```
