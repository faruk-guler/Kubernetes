# Volume Snapshots ve Volume Cloning

Kubernetes üzerinde durumlu (stateful) uygulamaların veri güvenliğini sağlamak, test ortamları için veritabanlarını klonlamak veya kritik güncellemeler öncesinde anlık kurtarma noktaları oluşturmak için iki temel gelişmiş depolama mekanizması kullanılır:

1. **VolumeSnapshot:** Bir PersistentVolume'ün (PV) belirli bir andaki salt okunur anlık görüntüsünü (snapshot) alır.
2. **Volume Cloning:** Çalışan bir PVC'nin (PersistentVolumeClaim) aynı isim alanı (namespace) altında birebir ve aktif yeni bir kopyasını (klon) oluşturur.

---

## 1. VolumeSnapshot Kurulumu ve CRD Tanımları

VolumeSnapshot özelliğinin kullanılabilmesi için kümenizde CSI snapshot denetleyicisinin (external-snapshotter) ve gerekli Custom Resource Definitions (CRD) tanımlarının kurulu olması gerekir:

```bash
# 1. Gerekli Custom Resource Definitions (CRD) tanımlarını uygulayın
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# 2. Merkezi Snapshot Denetleyicisini (Snapshot Controller) kurun
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
```

---

## 2. VolumeSnapshotClass ve Snapshot Alma

Bir disk anlık görüntüsü alabilmek için, depolama sınıfını belirten bir **VolumeSnapshotClass** nesnesine ihtiyaç duyulur.

### A. VolumeSnapshotClass Tanımı

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: longhorn-snapshot-class
driver: driver.longhorn.io # Depolama sürücüsü
deletionPolicy: Delete # Snapshot silindiğinde fiziksel yedeği de sil
```

### B. VolumeSnapshot Tanımı (Yedek Alma)

Aşağıdaki manifest ile mevcut `production-db-pvc` isimli diskin anlık yedeği alınır:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: db-snapshot-v1
  namespace: production
spec:
  volumeSnapshotClassName: longhorn-snapshot-class
  source:
    persistentVolumeClaimName: production-db-pvc
```

```bash
# Snapshot durumunu sorgulamak için:
kubectl get volumesnapshot -n production
# 'READYTOUSE' kolonu True olana kadar beklenir.
```

---

## 3. Snapshot'tan Veriyi Geri Yükleme (Restore)

Alınan anlık yedekten (snapshot) yeni bir PVC oluşturarak verileri kurtarmak veya başka bir podda kullanmak için:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-db-pvc
  namespace: production
spec:
  storageClassName: longhorn
  dataSource:
    name: db-snapshot-v1
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

---

## 4. Volume Cloning (Disk Klonlama)

Herhangi bir snapshot nesnesi oluşturmadan, çalışan aktif bir PVC'nin doğrudan birebir kopyasını oluşturmak için PVC tanımındaki `dataSource` alanına mevcut PVC hedef gösterilir:

```yaml
spec:
  dataSource:
    name: production-db-pvc
    kind: PersistentVolumeClaim # VolumeSnapshot yerine doğrudan kaynak PVC belirtilir
```

> [!NOTE]
> **Klonlama Sınırı:** Disk Klonlama (Volume Cloning) işlemi, kaynak PVC ile hedef PVC'nin kesinlikle **aynı namespace (ad alanı)** altında olmasını gerektirir. Farklı bir namespace'e veri taşımak istiyorsanız önce `VolumeSnapshot` almalı ve yeni namespace altından o snapshot'ı `dataSource` göstererek PVC oluşturmalısınız.
