# Depolama Temelleri (Storage Fundamentals)

Kubernetes'te pod'lar geçicidir (ephemeral). Pod silindiğinde içindeki veriler de silinir. Veriyi kalıcı hale getirmek için depolama (Storage) nesneleri kullanılır.

---

## Ephemeral (Geçici) Volume Türleri

Bu türler pod ile birlikte ölürler, ancak pod içindeki konteynerler arasında veri paylaşımı sağlarlar.

### 1. emptyDir
Pod bir node'a atandığında oluşturulur. Pod yaşadığı sürece veri korunur. Konteynerler arası veri paylaşımı için idealdir.
```yaml
volumes:
- name: cache-volume
  emptyDir: {}
```

### 2. hostPath
Node üzerindeki bir dizini pod'a mount eder. Genellikle log toplama veya yerel donanım erişimi için kullanılır.
```yaml
volumes:
- name: log-dir
  hostPath:
    path: /var/log/app
    type: DirectoryOrCreate
```

---

## Kalıcı Depolama (PV ve PVC)

Kubernetes, depolama yönetimini uygulama geliştiriciden (PVC) ve altyapı yöneticisinden (PV) ayırır.

### PersistentVolume (PV)
Cluster genelindeki "fiziksel" disk kaynağıdır (AWS EBS, NFS, Local SSD). Admin tarafından oluşturulur.

### PersistentVolumeClaim (PVC)
Kullanıcının depolama talebidir. "Bana 10GB ReadWriteOnce bir disk ver" der. Kubernetes uygun bir PV'yi bu PVC'ye bağlar (Binding).

---

## StorageClass (Dinamik Oluşturma)

PV'leri manuel oluşturmak yerine, disklerin otomatik (Dynamic Provisioning) oluşturulmasını sağlar.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: ebs.csi.aws.com   # EBS CSI Driver (2026 standardı)
parameters:
  type: gp3
  encrypted: "true"          # Şifreleme varsayılan açık olmalı
reclaimPolicy: Retain          # PVC silinse de disk kalsın
allowVolumeExpansion: true     # Diski sonra büyütmeye izin ver
volumeBindingMode: WaitForFirstConsumer  # Pod hangi AZ'deyse orada oluştur
```

---

## Kullanım Örneği

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: standard
---
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    volumeMounts:
    - name: storage
      mountPath: /var/lib/mysql
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: mysql-data-pvc
```

---

## Pratik Desen: Paylaşımlı Depolama (Reader-Writer)

Birçok pod'un aynı veriyi okuduğu, ancak sadece bir pod'un o veriyi güncellediği senaryolarda `ReadWriteMany` (RWX) modu kullanılır.

**Örnek Senaryo (yyy Nugget):**
- **Writer Pod (Yazıcı):** Alp imajı üzerinde bir script ile sürekli `/html/index.html` dosyasına veri yazar.
- **Reader Pods (Okuyucular):** Nginx imajı üzerinde aynı volume'u mount ederek bu dosyayı web üzerinden yayınlar.

```yaml
# Writer (Yazıcı)
spec:
  containers:
  - name: writer
    image: alpine
    command: ["/bin/sh", "-c", "while true; do date >> /html/index.html; sleep 5; done"]
    volumeMounts:
    - name: shared-data
      mountPath: /html
# Reader Deployment (Okuyucular)
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:stable-alpine
        volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
          readOnly: true
```

---

## Operasyonel İpuçları (Black Belt)

1.  **Access Modes:**
    - `ReadWriteOnce (RWO):` Tek bir node tarafından okunabilir/yazılabilir. (Blok storage).
    - `ReadWriteMany (RWX):` Aynı anda birçok node tarafından (NFS/Ceph) kullanılabilir.
2.  **Reclaim Policy:**
    - `Delete:` PVC silinince fiziksel disk de gider.
    - `Retain:` PVC silinse de veri nodes/cloud üzerinde kalır (Admin manuel siler).
3.  **CSI (Container Storage Interface):** Modern Kubernetes'te tüm depolama işlemleri CSI plugin'leri üzerinden yürütülür. Detaylar için `CSI Drivers & Dynamic Provisioning.md` dosyasına bakın.

---
