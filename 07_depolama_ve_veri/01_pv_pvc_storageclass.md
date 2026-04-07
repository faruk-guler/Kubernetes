# PV, PVC ve StorageClass

## 1.1 Depolama Kavramları

| Kavram | Açıklama |
|:---|:---|
| **PersistentVolume (PV)** | Cluster admini tarafından sağlanan depolama birimi |
| **PersistentVolumeClaim (PVC)** | Kullanıcının depolama talebi |
| **StorageClass** | Dinamik PV üretme şablonu |

## 1.2 StorageClass'lar

### Longhorn (Bare Metal için)

```bash
# Longhorn kurulumu
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=3

# Varsayılan StorageClass yap
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-replicated
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain        # Volume silindiğinde veriyi koru
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  diskSelector: "ssd"        # Sadece SSD diskler kullan
```

### AWS EBS / GCP PD (Bulut)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer   # Pod schedule olana kadar bekle
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
```

## 1.3 PVC ile Depolama Talebi

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: production
spec:
  accessModes:
  - ReadWriteOnce          # Bir node'da okuma/yazma
  storageClassName: longhorn-replicated
  resources:
    requests:
      storage: 20Gi
```

Access Mode'ler:

| Mode | Kısaltma | Açıklama |
|:---|:---:|:---|
| ReadWriteOnce | RWO | Tek node, okuma+yazma |
| ReadOnlyMany | ROX | Çok node, sadece okuma |
| ReadWriteMany | RWX | Çok node, okuma+yazma |
| ReadWriteOncePod | RWOP | Tek pod, okuma+yazma |

## 1.4 VolumeSnapshot ile Anlık Yedek

```yaml
# Snapshot al
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: db-backup-$(date +%Y%m%d)
  namespace: production
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: postgres-data

# Snapshot'tan PVC oluştur
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-restored
spec:
  dataSource:
    name: db-backup-20260402
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn-replicated
  resources:
    requests:
      storage: 20Gi
```

## 1.5 Volume Genişletme

```bash
# PVC boyutunu artır
kubectl patch pvc app-data -n production -p \
  '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Durum kontrolü
kubectl get pvc app-data -n production
```

> [!NOTE]
> StorageClass'ın `allowVolumeExpansion: true` olması ve PVC'nin `Bound` durumunda olması gerekir. Longhorn ve çoğu CSI driver online genişletmeyi destekler.

## 1.6 Uygulamalı Örnek: NFS Sunucu ve PV Kurulumu

Dinamik provisioner'ın olmadığı bare-metal ortamlarda en yaygın yöntem harici bir NFS sunucusu kullanmaktır.

### 1. NFS Sunucu Hazırlığı (Master veya Ayrı Node)
```bash
# NFS sunucusunu kur
sudo apt update && sudo apt install nfs-kernel-server -y

# Paylaşılacak dizini oluştur ve yetkilendir
sudo mkdir -p /nfs/kubedata/projeler
sudo chown nobody:nogroup /nfs/kubedata/projeler
sudo chmod 777 /nfs/kubedata/projeler

# İzinleri ayarla (/etc/exports)
# */nfs/kubedata *(rw,sync,no_subtree_check,no_root_squash)
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

### 2. Worker Node Hazırlığı
```bash
# Tüm worker node'larda NFS client paketi yüklü olmalıdır
sudo apt install nfs-common -y
```

### 3. Kubernetes PersistentVolume (PV) Tanımı
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany          # NFS çoklu erişimi destekler
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /nfs/kubedata/projeler
    server: <NFS_SUNUCU_IP>
```

### 4. Kubernetes PersistentVolumeClaim (PVC) Tanımı
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""       # Manuel PV eşleşmesi için boş bırakılmalıdır
  resources:
    requests:
      storage: 5Gi           # PV boyutundan küçük veya eşit olmalı
```

---
*← [Ana Sayfa](../README.md)*
