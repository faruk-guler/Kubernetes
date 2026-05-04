# Troubleshooting: Storage

Depolama sorunları sessizce gelir — pod çalışır ama veri yazamaz, PVC sonsuza dek Pending kalır, mount başarısız olur. Bu bölüm her senaryo için sistematik tanı yöntemini gösterir.

---

## PVC Pending Durumunda Kaldı

Bu en yaygın storage sorunudur. PVC oluşturuldu ama Bound olmadı.

```bash
# PVC durumunu kontrol et
kubectl get pvc -n <namespace>
# STATUS: Pending → Bound olmadı

# Detaylı tanı
kubectl describe pvc <pvc-adı> -n <namespace>
# Events bölümüne bak
```

### Olası Nedenler

#### 1. StorageClass bulunamadı
```bash
# Mevcut StorageClass'ları listele
kubectl get storageclass

# PVC'de belirtilen storageClassName doğru mu?
kubectl get pvc <pvc> -o jsonpath='{.spec.storageClassName}'

# Default StorageClass var mı? (PVC'de storageClassName boşsa)
kubectl get sc | grep "(default)"

# StorageClass'ı default yap
kubectl patch storageclass <sc-adı> \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

#### 2. Uygun PV yok (Static Provisioning)
```bash
# Mevcut PV'leri listele
kubectl get pv
# Available PV var mı? Etiketleri PVC selector'ıyla eşleşiyor mu?

# PV - PVC binding kuralları:
# - accessModes eşleşmeli
# - capacity yeterli olmalı
# - storageClassName eşleşmeli
# - volumeMode eşleşmeli (Filesystem/Block)
```

#### 3. CSI Driver / Provisioner çalışmıyor
```bash
# StorageClass'ın provisioner'ı nedir?
kubectl get sc <sc-adı> -o jsonpath='{.provisioner}'

# İlgili CSI driver pod'ları çalışıyor mu?
kubectl get pods -A | grep -i "longhorn\|csi\|ebs\|nfs"

# CSI driver event'leri
kubectl describe pvc <pvc> | grep -A20 "Events"
# "waiting for a volume to be created" → provisioner çalışmıyor
```

#### 4. WaitForFirstConsumer (Bekleme Modu)
```bash
# Bazı StorageClass'lar pod schedule edilene kadar PV oluşturmaz
kubectl get sc <sc-adı> -o jsonpath='{.volumeBindingMode}'
# Değer: WaitForFirstConsumer → Pod çalışmadan PVC Bound olmaz (NORMAL DAVRANISH)
# Değer: Immediate         → Hemen Bound olmalı
```

---

## Volume Mount Hataları

### Pod "ContainerCreating" durumunda takılı kaldı

```bash
kubectl describe pod <pod> -n <namespace>
# Şuna benzer event aranır:
# "Unable to attach or mount volumes"
# "Timeout expired waiting for volumes"
# "Multi-Attach error for volume"
```

#### Multi-Attach Hatası (ReadWriteOnce)
```bash
# Hata: "Multi-Attach error for volume ... Volume is already exclusively attached to one node"
# Neden: RWO (ReadWriteOnce) disk zaten başka bir node'a bağlı

# Eski pod'u bul (belki Terminating'de)
kubectl get pods -A -o wide | grep <pvc-adı veya node>

# Pod silinmek üzere ama disk bırakmıyor
kubectl delete pod <eski-pod> --grace-period=0 --force

# Disk detach işlemini zorla (cloud provider'a göre değişir)
```

#### Node'da Mount Başarısız
```bash
# Node üzerinde kontrol (SSH ile)
mount | grep <pvc-adı>
dmesg | grep -i "mount\|nfs\|ext4\|xfs" | tail -20

# NFS mount sorunu
showmount -e <nfs-server-ip>
mount -t nfs <nfs-server>:/path /mnt/test  # Manuel test

# Longhorn volume detach/attach sorunları
kubectl get volumes.longhorn.io -n longhorn-system
```

---

## StatefulSet Storage Sorunları

```bash
# StatefulSet PVC'leri kontrol et
kubectl get pvc -n <namespace> | grep <statefulset-adı>
# Her pod için ayrı PVC olmalı: data-<sts-adı>-0, data-<sts-adı>-1 ...

# StatefulSet scale down sonrası PVC'ler silinmez (bu beklenen davranış)
# Yeniden scale up olduğunda aynı PVC yeniden bağlanır

# PVC'yi silmek istiyorsanız manuel:
kubectl delete pvc data-<sts>-0 -n <namespace>
```

---

## Volume Dolu (No Space Left on Device)

```bash
# Pod logları "no space left on device" hatasını gösteriyorsa

# PVC'nin ne kadar dolduğunu gör
kubectl exec <pod> -- df -h /data

# PV kapasitesi gerçekte ne kadar?
kubectl get pvc <pvc> -o jsonpath='{.status.capacity.storage}'

# Volume genişletme (StorageClass allowVolumeExpansion: true olmalı)
kubectl patch pvc <pvc> -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Genişleme durumu
kubectl describe pvc <pvc> | grep -A5 "Conditions\|Events"
# FileSystemResizePending → Pod yeniden başlatılmalı
```

---

## Persistent Volume Reclaim Sorunları

```bash
# PVC silindi ama PV hâlâ "Released" durumunda (yeniden kullanılamıyor)
kubectl get pv | grep Released

# Reclaim Policy nedir?
kubectl get pv <pv> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
# Retain → PVC silinse de PV kalmaya devam eder, claimRef manuel temizlenmeli
# Delete → Otomatik silindi ama cloud'da disk kaldıysa: cloud console'dan sil
# Recycle → Deprecated, kullanma

# Released PV'yi yeniden kullanılabilir hale getir
kubectl patch pv <pv> -p '{"spec":{"claimRef":null}}'
```

---

## etcd ve ConfigMap/Secret Depolama

```bash
# etcd veri bütünlüğü kontrolü
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Secret şifrelenmiş mi? (encryption at rest)
kubectl get secret <secret> -o yaml
# data alanındaki değerler base64 encoded — açık metin DEĞİL
# etcd'de şifreliyse: EncryptionConfiguration tanımlanmış demektir
```

---

## Longhorn Spesifik Sorunlar

```bash
# Longhorn UI'dan volume durumuna bak
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80

# CLI ile volume durumu
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system | grep -v Running

# Replica rebuild sorunu
kubectl describe volume.longhorn.io <vol> -n longhorn-system
# "replica rebuild failed" → Storage disk dolu mu? Node sağlıklı mı?

# Longhorn disk ekle
kubectl label nodes <node> node.longhorn.io/create-default-disk=true
```

---

## Genel Storage Tanı Akışı

```
Storage sorunu
     │
     ├── PVC Pending
     │     ├── StorageClass doğru mu? → kubectl get sc
     │     ├── Provisioner çalışıyor mu? → kubectl get pods -A | grep csi
     │     └── WaitForFirstConsumer mı? → sc volumeBindingMode
     │
     ├── Mount Başarısız (ContainerCreating takılı)
     │     ├── Multi-Attach? → RWO disk başka node'da mı?
     │     ├── Node mount sorunu → dmesg | grep mount
     │     └── NFS/Longhorn erişim sorunu
     │
     ├── Volume Dolu
     │     ├── kubectl exec pod -- df -h
     │     └── PVC genişlet (allowVolumeExpansion)
     │
     └── PV Released / Reclaim sorunu
           └── kubectl patch pv ... claimRef null
```
