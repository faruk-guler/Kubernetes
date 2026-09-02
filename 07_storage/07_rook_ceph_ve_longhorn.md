# Cloud-Native Dağıtık Depolama: Rook/Ceph ve Longhorn

Bare-metal, on-premise (şirket içi) veri merkezleri veya Edge cihazlarda Kubernetes çalıştırdığınızda, AWS EBS veya Google PD gibi hazır bulut diskleri bulunmaz. Bu ortamda verilerin kaybolmaması (yüksek erişilebilirlik) için veriyi kümeyi oluşturan sunucuların yerel disklerine **dağıtık (distributed)** ve **kopyalı (replicated)** bir şekilde yazmanız gerekir.

Bu ihtiyacı çözen en popüler iki CNCF depolama çözümü **Rook (Ceph)** ve **Longhorn**'dur.

---

## 1. Rook ve Ceph (Kurumsal Ölçek)

**Rook**, açık kaynaklı bir bulut yerleşik depolama orkestratörüdür. Kubernetes için Ceph kümelerini otomatikleştirir, yönetir ve ölçeklendirir.
**Ceph**, nesne (Object - S3), blok (Block) ve dosya (File) depolama arabirimleri sunan, devasa ölçekli dağıtık bir depolama sistemidir.

Rook, Ceph'in karmaşıklığını gizler ve onu bir Kubernetes Operatörü (Operator) aracılığıyla Kubernetes nesnelerine (CRD) dönüştürür.

### Rook/Ceph Mimarisi
1. **Rook Operator:** Ceph bileşenlerini (MON, OSD, MGR, MDS) Kubernetes podları olarak ayağa kaldırır.
2. **Ceph OSD (Object Storage Daemon):** Düğümlerdeki yerel disklere (örneğin bağlanmış, formatlanmamış boş SSD'ler) doğrudan erişerek veriyi yazar.
3. **StorageClass:** Rook, Ceph blok cihazları için bir StorageClass sunar (`rook-ceph-block`). Podlar PVC (PersistentVolumeClaim) talep ettiğinde Rook otomatik olarak Ceph üzerinden sanal bir disk açar.

### Rook/Ceph Kurulumu (Kısa Özet)
```bash
# 1. Rook Operator Kurulumu
kubectl create -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/common.yaml
kubectl create -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/operator.yaml

# 2. Ceph Kümesinin (Cluster) Oluşturulması
# İlgili manifesto 'manifests/07_rook_ceph_cluster.yaml' dosyasında bulunmaktadır.
kubectl create -f manifests/07_rook_ceph_cluster.yaml
```

### Ne Zaman Rook/Ceph Kullanılmalı?
* PetaBayt (PB) seviyesinde devasa depolama gereksinimleri olduğunda.
* Hem Blok (RBD), hem Dosya (CephFS - ReadWriteMany), hem de Nesne (Object/S3) depolamasına aynı anda ihtiyaç duyulduğunda.
* Yüksek oranda kurumsal performans ve veri dayanıklılığı arandığında.

---

## 2. Longhorn (Hafif ve Kubernetes-Native)

**Longhorn**, SUSE (Rancher) tarafından geliştirilen, kullanımı son derece kolay, hafif ve tamamen mikroservis mimarisine sahip CNCF (Incubating) dağıtık blok depolama çözümüdür.

Ceph'in aksine, Longhorn sadece **Blok Depolama** (Block Storage) sağlar. Her Longhorn volume'ü, Kubernetes podlarından oluşan ayrı bir mikroservistir.

### Longhorn Mimarisi
1. **Engine (Motor):** Her volume için ayrı bir Engine podu çalıştırılır. Bu sayede bir volume'de yaşanan hata diğerlerini etkilemez.
2. **Replica:** Veriler asenkron/senkron olarak kümedeki diğer düğümlerin yerel disklerine kopyalanır (Örn: 3 kopya).
3. **UI (Arayüz):** Longhorn, diskleri, yedeklemeleri ve kopyaları yönetmek için çok kullanıcı dostu yerleşik bir web arayüzü sunar.

### Longhorn Kurulumu
```bash
# Helm ile Kurulum
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

### Longhorn'un Öne Çıkan Özellikleri
* **Sıfır Yapılandırma:** Disklere format atmaya veya LVM ayarlamaya gerek yoktur; düğümlerin `var/lib/longhorn` dizinini kullanabilir.
* **Yedekleme (Backup):** Verileri AWS S3, MinIO veya NFS sunucularına tek tıkla yedekleyebilir ve geri dönebilir.
* **DR (Disaster Recovery):** Pasif bir kümeye sürekli veri kopyalayarak felaket kurtarma senaryoları kurgulanabilir.

### Ne Zaman Longhorn Kullanılmalı?
* Kurulum ve bakım maliyetlerini minimumda tutmak isteyen ekipler.
* Ceph'in karmaşıklığına ihtiyaç duymayan, 10-50 node arası daha küçük/orta ölçekli kümeler.
* Edge bilişim senaryolarında, kısıtlı kaynaklara sahip ortamlarda.

---

## 3. Karşılaştırma Tablosu

| Özellik | Rook / Ceph | Longhorn |
| :--- | :--- | :--- |
| **Zorluk / Karmaşıklık** | Yüksek (Öğrenme eğrisi diktir) | Çok Düşük (Kur-Çalıştır) |
| **Depolama Tipleri** | Blok, Dosya (FS), Nesne (S3) | Sadece Blok (Block) |
| **Performans** | Çok Yüksek (Çekirdek/Donanım seviyesi) | Orta/Yüksek (Kullanıcı alanı) |
| **Arayüz (UI)** | Ceph Dashboard (Orta zorluk) | Longhorn UI (Çok sezgisel) |
| **Yedekleme/DR** | Karmaşık (RBD Mirroring, vb.) | Çok Kolay (S3 entegrasyonu yerleşik) |

> **SRE İpucu:** Eğer on-premise (kendi donanımınız) üzerinde Kubernetes koşturuyorsanız ve ekibinizde depolama/storage uzmanı yoksa, her zaman **Longhorn** ile başlayın. Ceph, yanlış yapılandırıldığında verileri kurtarması en zor ve stresli sistemlerden biridir.
