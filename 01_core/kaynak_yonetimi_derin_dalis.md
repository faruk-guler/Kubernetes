# Kaynak İstekleri ve Limitleri

Kubernetes kümenizde 10 adet sunucu (Node) ve her birinde 16 GB RAM olduğunu düşünün. Yeni bir veritabanı pod'u oluşturduğunuzda, Kubernetes bu pod'u hangi sunucuya koyacağına nasıl karar verir? Eğer sunuculardan birinin CPU'su tamamen doluysa, pod'u oraya gönderirse sistem çöker mi?

İşte bu süreci sorunsuz yöneten bileşen **Scheduler (Zamanlayıcı)** dır. Ancak Scheduler'ın doğru karar verebilmesi için sizin ona podlarınızın ne kadar kaynağa (CPU ve RAM) ihtiyacı olduğunu söylemeniz zorunludur.

---

## 1. Requests vs Limits (İstekler ve Sınırlar)

Her konteynerin kaynak tüketimini iki temel kavramla yönetiriz:

### Requests (Garanti Edilen İstek)

* "Bu pod'un sağlıklı çalışabilmesi için **en az** ne kadar CPU ve RAM'e ihtiyacı var?"
* Scheduler bir pod'u bir sunucuya yerleştirmeden önce o sunucunun boş kapasitesine (Allocatable) bakar. Eğer sunucuda `Requests` miktarını karşılayacak kadar boş yer yoksa, pod o sunucuya asla yerleştirilmez.
* *Örnek:* `requests.memory: "512Mi"` derseniz, Kubernetes bu pod'a o belleği garanti eder.

### Limits (Üst Sınır)

* "Bu pod çılgına dönüp kontrolden çıkarsa (memory leak vs.), **en fazla** ne kadar kaynak tüketebilir?"
* Pod eğer `Limits` miktarını aşmaya çalışırsa Kubernetes devreye girer.
  * **Memory Aşımı:** Eğer pod memory limitini aşarsa Kubernetes o pod'u acımasızca "öldürür" (OOMKilled - Out of Memory) ve yeniden başlatır.
  * **CPU Aşımı:** Eğer pod CPU limitini aşarsa öldürülmez, ancak CPU'su darboğaza sokulur (Throttled) ve uygulama yavaşlar.

> [!WARNING]
> Üretim (Production) ortamlarındaki altın kural: **CPU için her zaman Requests ayarlayın, ancak Limits ayarlarken çok dikkatli olun.** Yanlış ayarlanmış bir CPU Limiti (Örn: `500m`), pod'un ani yük (spike) geldiğinde yavaşlamasına ve "CPU Throttling" sorunlarına yol açar. Ancak Memory için her ikisini de (Requests = Limits olacak şekilde) mutlaka ayarlayın.

---

## 2. QoS Sınıfları (Quality of Service)

Sunucunuzun 16 GB belleği tamamen dolduğunda ve yeni gelen bir sistemsel işlem RAM talep ettiğinde Kubernetes ne yapar? Cevap: Kaynakları kurtarmak için çalışan pod'lardan bazılarını **feda etmek (öldürmek) zorundadır.**

Kimin yaşayıp kimin öleceğine **QoS (Hizmet Kalitesi) Sınıfları** karar verir. Kubernetes bunu otomatik atar:

1. **Guaranteed (En Yüksek Koruma):** Eğer pod'unuzun tüm `Requests` ve `Limits` değerleri birbirine eşitse (Örn: Request=1GB, Limit=1GB) Kubernetes bu pod'u "Guaranteed" sınıfına koyar. Veritabanı gibi kritik servislerde kullanılır. Kaynak bittiğinde **en son** bu podlar öldürülür.
2. **Burstable (Orta Koruma):** Eğer pod'un `Limits` değeri `Requests` değerinden büyükse "Burstable" sınıfına girer. Çoğu standart uygulama bu sınıftadır.
3. **BestEffort (Sıfır Koruma):** Eğer pod'un hiçbir Request ve Limit değeri yoksa "BestEffort" olur. Kaynak sıkıntısı yaşandığında Kubernetes'in ilk feda edip öldüreceği (OOMKilled) zavallı pod'lar bunlardır. Test ortamları dışında asla kullanılmamalıdır!

---

## 3. LimitRange ve ResourceQuota

Her bir yazılımcının yazdığı manifest dosyalarını (YAML) tek tek kontrol edip "Acaba Limits eklemiş mi?" diye bakmak imkansızdır. Bunu otomatikleştirmeliyiz.

**LimitRange (Varsayılan Sınırlar):**
Bir yazılımcı Namespace'e pod gönderdiğinde, eğer içine `Requests` veya `Limits` yazmayı unutmuşsa, `LimitRange` devreye girer ve otomatik olarak sizin belirlediğiniz varsayılan değerleri (Örn: 200m CPU, 256Mi RAM) o pod'un içine yazar.

**ResourceQuota (Toplam Bütçe):**
Diyelim ki "DataScience" ekibine bir Namespace verdiniz. Yanlışlıkla yazdıkları bir kodla 500 tane pod oluşturup tüm kümenin belleğini sömürebilirler. `ResourceQuota` ile Namespace'in kendisine üst sınır (Bütçe) koyarsınız. *"Bu takımın Namespace'i toplamda en fazla 100 Pod açabilir ve 32 GB RAM harcayabilir."*

---

## 4. İleri Seviye: Dynamic Resource Allocation (DRA)

Kubernetes 1.31 ve sonrasında (2026 standardı) yapay zeka (AI) ve Machine Learning (Makine Öğrenimi) pod'ları için basit CPU ve RAM limitleri yetersiz kalmıştır.

Örneğin, pod'unuzun standart bir ekran kartına değil, *"Ağ hızı 400 Gbps olan, NVLink bağlantılı, tam olarak NVIDIA H100 model bir GPU'ya"* ihtiyacı varsa ne olacak?
İşte burada **Dynamic Resource Allocation (DRA)** devreye girer.

Yazılımcı, tıpkı depolamada PVC talep eder gibi bir **ResourceClaim** oluşturur.
"Bana şu özelliklere sahip donanımsal bir GPU ver."
Kubernetes (ve o donanımın kurulu olduğu DRA Sürücüsü) bu spesifik talebi okur, donanımı bulur, böler (MIG - Multi-Instance GPU) ve sadece o pod'un kullanımına özel olarak sunar.

---

## 5. Kapasite Planlama ve Performans (Capacity Planning)

Bir kümeyi yönetirken en sık karşılaşılan sorun "Gereğinden fazla kaynak harcamak (İsraf)" veya "Gereğinden az kaynak harcayıp sistemi çökertmek"tir.

Eğer yüzlerce pod'unuz yavaş çalışıyorsa sorun sadece pod'larda değildir, Kubernetes'in beyni olan **etcd** veritabanında darboğaz yaşıyor olabilirsiniz.

**Performans Optimizasyonu Altın Kuralları:**

1. **etcd Disk Hızı:** Kubernetes'in kalbi `etcd` veritabanıdır. Eğer etcd'nin veriyi diske yazma (fsync) hızı 10 milisaniyenin üstüne çıkarsa, tüm kümeniz felç olur. `etcd` çalıştıran (Control Plane) sunucularda mutlaka **NVMe SSD** kullanmalısınız.
2. **Kapasite Marjı:** "100 pod x 200m CPU = 20 CPU lazım" demek yanlıştır. İşletim sistemi (Kubelet, DaemonSet'ler, Loglayıcılar) her zaman kendine kaynak ayırır. Kapasite hesaplarken daima %30'luk bir pay (Buffer) bırakın.
3. **Yük Testi:** Sistemin limitlerini görmek için üretim ortamına benzer bir yerde **k6** veya **Locust** gibi araçlarla pod'larınıza sahte yük (Load Testing) gönderin ve ne zaman `CPU Throttling` yaşamaya başladıklarını izleyin.

Peki, basit bir pod "Bana 4 CPU ver" dediğinde, Kubernetes 4 CPU boşluğu olan 10 sunucu arasından **hangisini** seçecek? Veya "Ben Veritabanı poduyum, beni asla Frontend podlarıyla aynı sunucuya koyma!" kuralını nasıl yazacağız?
Bunun cevabı bir sonraki bölümümüz olan **Gelişmiş Zamanlama (Advanced Scheduling)** konusunda.
