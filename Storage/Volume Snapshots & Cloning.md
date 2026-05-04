# Volume Snapshots & Cloning

Kubernetes'te verinin korunması ve kopyalanması için iki temel mekanizma: **VolumeSnapshot** (yedeğe benzer, belirli andaki volume görüntüsü) ve **Volume Cloning** (mevcut PVC'nin birebir kopyası).

---

## VolumeSnapshot Nedir?

Bir PVC'nin belirli andaki anlık görüntüsüdür. Uygulama verisi bozulduğunda veya test ortamı oluşturulacağında kullanılır. Storage driver tarafından desteklenmesi gerekir (Longhorn, Ceph, EBS hepsi destekler).

### Gerekli CRD'ler

```bash
# VolumeSnapshot CRD'leri kur
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Snapshot controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
```

---

## VolumeSnapshotClass

```yaml
# Longhorn için
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: longhorn-snapshot-class
driver: driver.longhorn.io
deletionPolicy: Retain      # Snapshot'ı VolumeSnapshot silinse de sakla
                            # Delete → VolumeSnapshot silinince snapshot da silinir

---
# AWS EBS için
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snapshot-class
driver: ebs.csi.aws.com
deletionPolicy: Retain
```

---

## Snapshot Alma

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mysql-snapshot-20260425
  namespace: production
spec:
  volumeSnapshotClassName: longhorn-snapshot-class
  source:
    persistentVolumeClaimName: mysql-data-pvc    # Snapshot alınacak PVC
```

```bash
# Snapshot oluştur
kubectl apply -f snapshot.yaml

# Durumu kontrol et
kubectl get volumesnapshot -n production
# READYTOUSE: true olana kadar bekle

kubectl describe volumesnapshot mysql-snapshot-20260425 -n production
```

---

## Snapshot'tan Restore (Yeni PVC Oluştur)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-restored-pvc
  namespace: production
spec:
  storageClassName: longhorn
  dataSource:
    name: mysql-snapshot-20260425      # Snapshot adı
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi    # Snapshot boyutundan küçük olamaz
```

```bash
kubectl apply -f restored-pvc.yaml
kubectl get pvc mysql-restored-pvc -n production
# Bound olduktan sonra pod'a bağla
```

---

## Volume Cloning

Mevcut bir PVC'yi kaynak olarak kullanarak yeni PVC oluşturma. Snapshot gerektirmez, storage driver tarafından desteklenmeli.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-clone-pvc
  namespace: staging     # Kaynak ile aynı namespace olmalı!
spec:
  storageClassName: longhorn
  dataSource:
    name: mysql-data-pvc      # Kaynak PVC
    kind: PersistentVolumeClaim
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi    # Kaynak PVC ile aynı veya büyük olmalı
```

> [!NOTE]
> Volume cloning, kaynak ve hedef PVC'nin **aynı namespace'de** olmasını gerektirir. Cross-namespace kopyalama için önce snapshot al, sonra farklı namespace'de restore et.

---

## Otomatik Snapshot Politikası (Longhorn)

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"       # Her gece 02:00
  task: snapshot
  retain: 7                # Son 7 snapshot sakla
  concurrency: 1
  labels:
    backup: daily
```

```bash
# Volume'a recurring job ekle
kubectl label volume.longhorn.io <volume-adı> \
  -n longhorn-system \
  recurring-job.longhorn.io/daily-backup=enabled
```

---

## Snapshot Listesi ve Temizlik

```bash
# Tüm snapshot'lar
kubectl get volumesnapshot -A
kubectl get volumesnapshotcontent    # Cluster seviyesinde fiziksel snapshot

# Snapshot sil
kubectl delete volumesnapshot mysql-snapshot-20260425 -n production

# VolumeSnapshotContent'i de sil (deletionPolicy: Delete değilse otomatik silinmez)
kubectl delete volumesnapshotcontent <vsc-adı>

# Longhorn UI'dan snapshot yönetimi
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80
```

---

## Kullanım Senaryoları

| Senaryo | Çözüm |
|:--------|:------|
| Database yedeği önce test et | Snapshot al → restore et → test ortamında doğrula |
| Production → Staging kopyalama | Snapshot → Farklı namespace'de restore |
| Aynı namespace'de hızlı kopya | Volume Clone |
| Yanlışlıkla silinen veri | Snapshot'tan restore |
| Uygulama güncellemesi öncesi | Snapshot (rollback planı) |
| Rutin yedekleme | RecurringJob (Longhorn) veya Velero |
