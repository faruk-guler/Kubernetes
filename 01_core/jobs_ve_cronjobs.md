# StatefulSet, DaemonSet ve Job Kavramları

Önceki bölümde, çöken pod'ları anında yenileyen ve kesintisiz güncelleme (zero-downtime) sağlayan `Deployment` nesnesini inceledik. Deployment, "Stateless" (durumsuz/verisiz) uygulamalar (örneğin web sitenizin arayüzü veya API'niz) için mükemmeldir.

Ancak gerçek dünyada her uygulama sadece web arayüzünden ibaret değildir. Veritabanlarınız, her sunucuda çalışması zorunlu log toplayıcılarınız veya gece yarısı bir kere çalışıp kapanması gereken yedekleme görevleriniz vardır. İşte bu özel senaryolar için Kubernetes 3 farklı iş yükü (Workload) sunar.

---

## 1. Veritabanları için StatefulSet (Durumlu Uygulamalar)

Deployment ile oluşturulan pod'lar kimliksizdir ve isimleri rastgeledir (`web-7f8b4d-xkjl9`). Biri çöküp yenisi açıldığında isim, IP ve bağlı olduğu disk tamamen değişir. Web sunucusu için bu sorun değildir, peki ya **MySQL veritabanı** çöküp yeni bir diskle boş bir şekilde açılırsa? Bu bir felakettir.

İşte verisini diskte tutmak zorunda olan uygulamalar için **StatefulSet** kullanılır.

### Deployment vs StatefulSet Farkı

| Özellik | Deployment | StatefulSet |
| :-------- | :----------- | :------------ |
| **Pod İsmi** | Rastgele (`api-7f8b...`) | Sıralı ve Sabit (`mysql-0`, `mysql-1`) |
| **Bağlanan Disk (Volume)** | Ortak veya Geçici | Her Pod'a Özel Kalıcı Disk (PVC) |
| **Açılma/Kapanma Sırası** | Hepsi aynı anda paralel | Sırayla (Önce 0, sonra 1 açılır) |
| **Kullanım Alanı** | Web API, Frontend | MySQL, Redis Cluster, Kafka |

> [!IMPORTANT]
> StatefulSet'in en büyük sihri `volumeClaimTemplates` özelliğidir. `mysql-1` podu çökse bile, Kubernetes onu `mysql-1` ismiyle yeniden ayağa kaldırır ve eski `mysql-1` diskini noktası noktasına yeni pod'a bağlar. Hiçbir veri kaybı yaşanmaz. Ayrıca bu sabit isimlerin diğer pod'lar tarafından DNS ile bulunabilmesi için yanına her zaman bir **Headless Service** kurulması zorunludur.

---

## 2. Her Node'da Bir Pod (DaemonSet)

Diyelim ki kümenizde 50 adet sunucu (Node) var. Uygulamalarınızın loglarını toplayıp merkezi bir yere göndermek için bir "Log Toplayıcı" program (örneğin Filebeat) kurmak istiyorsunuz.

Eğer bunu Deployment ile (replicas: 50) yaparsanız, Kubernetes tesadüfen 5 pod'u aynı sunucuya koyabilir, bazı sunucular ise boş kalır. Bu da o boş sunuculardaki logların kaybolması demektir.

Çözüm **DaemonSet** nesnesidir:

- **Kural:** DaemonSet, istisnasız bir şekilde kümedeki "Her Node'da tam olarak 1 adet" kopya çalıştırır.
- Eğer kümeye yeni bir Node eklerseniz, DaemonSet anında fark eder ve o Node'a da 1 adet kopya gönderir.
- **Kullanım Alanları:** Log toplayıcılar (FluentBit, Filebeat), Güvenlik tarayıcıları (Falco), Ağ eklentileri (Cilium, Calico CNI).

---

## 3. Kısa Süreli Görevler (Job ve CronJob)

Deployment, StatefulSet ve DaemonSet'in ortak özelliği, içlerindeki kodun **sonsuza kadar çalışmasının beklenmesidir**. Eğer içlerindeki uygulama işini bitirip (`exit 0` vererek) kapanırsa, Kubernetes bunu "Çöktü" sanır ve hemen yeniden başlatır.

Peki ya sadece 1 kere çalışıp kapanmasını istediğimiz görevler? (Örneğin: Veritabanı yedeğini alıp S3'e yüklemek veya devasa bir resmi işlemek). Bu durumlarda **Job** nesnesi kullanılır.

### Job (Tek Seferlik İşlem)

Sadece belirlenen görevi başarıyla tamamlayıp kapanan pod'lardır.

- **`completions`:** Bu işin toplamda kaç pod tarafından başarıyla bitirilmesi gerektiğini belirler (Örn: 10 adet resim işlenecek).
- **`parallelism`:** İşin hızlandırılması için aynı anda en fazla kaç pod'un çalışabileceğini belirler (Aynı anda 2 pod çalışıp 10 işi eritebilir).
- **`backoffLimit`:** Eğer pod hata verip çökerse (`exit 1`), Kubernetes'in bu işten pes etmeden önce kaç kere yeniden deneyeceğini belirler (Örn: 3 kere dene, olmazsa vazgeç).

### CronJob (Zamanlanmış Görevler)

Linux dünyasındaki `crontab` yapısının Kubernetes halidir.

- Belirlediğiniz takvime göre (örneğin: her gece saat 03:00'te) arka planda otomatik olarak yeni bir **Job** tetikler.
- **`suspend`:** İstenildiği zaman CronJob'un çalışması geçici olarak durdurulabilir.
- **`ttlSecondsAfterFinished`:** Cluster'ın eski görevlerin loglarıyla çöplüğe dönmemesi için, iş bittikten sonra pod'un kaç saniye sonra silineceğini belirler (Örn: 3600 saniye sonra sil).

> [!TIP]
> CronJob kullanırken uygulamanızın (kodunuzun) **Idempotent (Eşgüçlü)** olmasına dikkat edin. Kubernetes'te ağ kesintileri nedeniyle bazen aynı gece için tesadüfen 2 adet pod tetiklenebilir. Kodunuz "Eğer yedek alındıysa tekrar alma" mantığını içermelidir.

Tüm bu nesneler, oluşturuldukları andan kapanana kadar bir yaşam döngüsünden geçerler. Ancak Kubernetes bu uygulamaların iç dünyasında neler olup bittiğini, uygulamanın donup donmadığını nasıl anlar?

Bir sonraki bölümde **Probes (Sağlık Taramaları)** ile uygulamalarımıza nasıl can suyu vereceğimizi öğreneceğiz.
