# PV, PVC ve StorageClass

`emptyDir` veya `hostPath` gibi geçici depolama yöntemleri podun ömrüne bağlı çalışır. Pod silindiğinde veya başka bir düğüme (node) taşındığında veriler kaybolur. Kalıcı veri depolama ihtiyacını çözmek için Kubernetes **PersistentVolume (PV)** ve **PersistentVolumeClaim (PVC)** mekanizmalarını sunar.

---

## 1. PersistentVolume (PV) — Kalıcı Depolama Alanı

Persistent Volume (PV), sistem yöneticileri tarafından manuel olarak veya bir StorageClass aracılığıyla dinamik olarak oluşturulan gerçek depolama alanını temsil eder.

### Örnek NFS PV Manifestosu

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pv_pvc_ve_storageclass_manifest_1.yaml](../Manifests/06_storage/pv_pvc_ve_storageclass_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Kritik PV Ayarları

* **accessModes:**
  * **ReadWriteOnce (RWO):** Sadece tek bir düğüm tarafından okuma/yazma olarak bağlanabilir (Blok diskler).
  * **ReadOnlyMany (ROX):** Aynı anda birçok düğüm tarafından salt okunur bağlanabilir.
  * **ReadWriteMany (RWX):** Aynı anda birçok düğüm tarafından okuma/yazma olarak bağlanabilir (NFS/Cephfs).
* **persistentVolumeReclaimPolicy:**
  * **Retain:** PVC silindiğinde PV ve veri diskte korunur. Yönetici elle silmelidir.
  * **Delete:** PVC silindiğinde PV ve buluttaki fiziksel disk otomatik olarak silinir.

---

## 2. PersistentVolumeClaim (PVC) — Depolama Talebi

Geliştiriciler podlarına doğrudan bir PV bağlayamazlar. Bunun yerine, cluster'da bulunan mevcut PV'ler arasından kendi ihtiyaçlarına uygun olanı talep etmek için bir **PersistentVolumeClaim (PVC)** nesnesi oluştururlar.

### Örnek PVC Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pv_pvc_ve_storageclass_manifest_2.yaml](../Manifests/06_storage/pv_pvc_ve_storageclass_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Kubernetes, bu talebi aldığında `storageClassName`, `accessModes` ve `storage` boyutunun uygunluğunu kontrol ederek otomatik olarak uygun bir PV ile eşleştirir (Binding).

---

## 3. Neden Rol Ayrımı Yapılır?

Kubernetes depolama altyapısını ikiye bölerek sistem yöneticisi (Admin) ile uygulama geliştiricisi (Developer) rollerini ayırır:

1. **Yönetici (Admin):** Depolama donanımına (AWS EBS, NFS, Ceph vb.) erişebilir durumdadır. Depolama alanlarını hazırlar ve PV'leri yazar. Geliştiricinin NFS sunucusunun IP adresini bilmesini istemez.
2. **Geliştirici (Developer):** Donanım detaylarını bilmeden sadece "bana 5GB disk lazım" der ve PVC yazar.
3. **Taşınabilirlik (Portability):** Bu model sayesinde uygulama kodlarınız (PVC tanımlarınız) taşınabilir hale gelir. Aynı PVC tanımı lokal ortamda NFS ile çalışırken, AWS üzerinde EBS ile çalışır.

---

## 4. Dinamik Depolama ve StorageClass

Büyük Kubernetes kümelerinde her disk talebi için manuel PV yazılması pratik değildir. **StorageClass**, bir PVC oluşturulduğu anda arka planda otomatik olarak (on-demand) PV oluşturulmasını sağlayan bir şablondur.

### Örnek AWS EBS CSI StorageClass Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pv_pvc_ve_storageclass_manifest_3.yaml](../Manifests/06_storage/pv_pvc_ve_storageclass_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
