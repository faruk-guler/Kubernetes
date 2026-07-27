# Depolama Temelleri (Storage Fundamentals)

Konteynerler doğaları gereği **geçicidir (ephemeral)**. Bir pod silindiğinde veya başka bir sunucuya (Node) taşındığında, podun içinde yaratılan veya değiştirilen tüm dosyalar sonsuza dek silinir. Stateless (Durumsuz) dediğimiz ve sadece hesaplama yapan bir web sunucusu için bu mükemmel bir özelliktir.

Ancak uygulamanız bir veritabanıysa (PostgreSQL, MongoDB) veya kullanıcıların yüklediği faturaları tutan bir PDF arşivi ise, verilerinizin podun ölümüyle kaybolmasına izin veremezsiniz. Kubernetes, bu verileri kalıcı hale getirmek için karmaşık ancak son derece esnek bir depolama (Storage) mimarisi sunar.

---

## 1. Stateless (Durumsuz) vs Stateful (Durumlu) İş Yükleri

Kubernetes'te veri depolama ihtiyacını anlamak için uygulamanızın karakteristiğini bilmelisiniz:

* **Stateless (Durumsuz):** Veriyi kendisinde tutmayan, veriyi işleyip dışarı aktaran uygulamalardır. Örneğin bir Nginx sunucusu veya bir Node.js REST API. Eğer bu pod çökerse, Kubernetes yenisini açar ve kimse bir veri kaybı yaşamaz. Bunlar için genellikle Kalıcı Depolama'ya (Persistent Storage) ihtiyaç yoktur.
* **Stateful (Durumlu):** Veriyi kendi diskinde tutmak zorunda olan uygulamalardır. Elasticsearch, Redis, PostgreSQL gibi. Eğer bu pod çökerse, yerine açılacak yeni pod'un eski veritabanı diskine (Volume) fiziksel olarak yeniden bağlanabilmesi gerekir. StatefulSet nesneleri ve Kalıcı Birimler (Persistent Volumes) tam olarak bu iş için tasarlanmıştır.

---

## 2. Kalıcı Olmayan (Ephemeral) Birimler

Bazen bir pod'un içindeki konteynerlerin sadece kendi aralarında geçici dosya paylaşımına veya geçici bir önbelleğe (cache) ihtiyacı olur. Bunlar sunucunun RAM'ini veya fiziksel diskini geçici olarak kullanır.

* `emptyDir`: Pod oluşturulduğunda tamamen boş bir klasör olarak başlar. Pod yaşadığı sürece verileri tutar. Pod silindiğinde veya Node'dan atıldığında veriler kalıcı olarak silinir. RAM üzerinde (tmpfs) çalışacak şekilde ayarlanarak çok hızlı bir bellek içi önbellek yaratılabilir.

---

## 3. Kalıcı Depolama Kavramları (Block, File, Object)

Veriyi kalıcı olarak (Pod silinse bile) saklamak istiyorsak, verinin fiziksel olarak hangi formatta tutulacağını seçmeliyiz. Kubernetes üç farklı depolama paradigmasını destekler:

### A. Blok Depolama (Block Storage)

Blok depolama, fiziksel bir SSD/HDD diskin formatlanmamış, saf (raw) halini doğrudan bir sunucuya bağlamak gibidir.

* **Özellikleri:** Ultra düşük gecikme (latency), yüksek performans.
* **Kubernetes'te Kullanımı:** Veritabanları (MySQL, PostgreSQL) için zorunludur. `ReadWriteOnce (RWO)` moduyla bağlanır. Yani aynı diski aynı anda sadece **tek bir Pod** okuyup yazabilir. İki farklı node'daki pod aynı bloğa aynı anda yazamaz (veri bozulması olur).
* **Bulut Karşılığı:** AWS EBS, Google Persistent Disk, Azure Disk.

### B. Dosya Depolama (File Storage / NAS)

Veriyi dosya ve klasör hiyerarşisi halinde ağ (Network) üzerinden sunan depolama tipidir.

* **Özellikleri:** Paylaşımlı erişim. Birçok sunucu aynı anda aynı klasöre erişebilir. Ağ üzerinden erişildiği için Blok depolamaya göre biraz daha yavaştır.
* **Kubernetes'te Kullanımı:** İçerik Yönetim Sistemleri (Wordpress), paylaşımlı config dosyaları veya log toplama merkezleri için idealdir. `ReadWriteMany (RWX)` moduyla bağlanır.
* **Bulut Karşılığı:** AWS EFS, Google Cloud Filestore, Azure Files (veya geleneksel NFS sunucuları).

### C. Nesne Depolama (Object Storage)

Veriyi hiyerarşik bir klasör yapısında değil, benzersiz bir kimlik (ID) ve meta-veri ile düz bir düzlemde saklar.

* **Özellikleri:** Teorik olarak sonsuz ölçeklenebilir, ucuzdur ancak okuma/yazma süreleri (latency) yüksektir. Geleneksel dosya sistemi arayüzü sunmaz (API üzerinden GET/PUT ile çalışılır).
* **Kubernetes'te Kullanımı:** Pod'lar direkt olarak Nesne depolamayı bir Volume (Disk) olarak monte edemezler (bunun için s3fs gibi aracı araçlar gerekir ancak önerilmez). Uygulamanız (kodunuz) doğrudan S3 API'leri ile konuşarak video/fotoğraf gibi büyük dosyaları buraya kaydeder.
* **Bulut Karşılığı:** AWS S3, Google Cloud Storage (GCS), Azure Blob Storage, MinIO (On-Premise).

---

## Özet

Kubernetes depolama ekosistemine girerken şu altın kuralı unutmayın: **"Veritabanları için Blok (RWO), paylaşımlı arşiv dosyaları için Dosya (RWX), devasa yedekler ve resim dosyaları için Nesne (API) depolama kullanılır."**

Peki Kubernetes, AWS veya Azure altyapısındaki bu fiziksel diskleri nasıl otomatik olarak yaratıp podlara bağlar? Bir sonraki bölümde CSI (Container Storage Interface) Sürücülerini ve Dinamik İstihsis (Dynamic Provisioning) yapısını inceleyeceğiz.
