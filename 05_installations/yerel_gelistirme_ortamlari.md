# Yerel Geliştirme Ortamları (Local Development)

Uygulamalarınızı canlı ortamdaki (Production) bir Kubernetes kümesine göndermeden önce, kodlarınızı kendi dizüstü bilgisayarınızda (localhost) test etmeniz gerekir. Aksi takdirde, her kod değişikliğinde uzak bir bulut sunucusuna imaj derleyip göndermek hem ciddi vakit (dakikalarca bekleme süresi) kaybettirir hem de bulut faturalarınızı artırır.

Bu ihtiyacı çözmek için "Yerel (Local) Kubernetes" araçları geliştirilmiştir. Bu araçlar, devasa bir Kubernetes kümesinin küçültülmüş bir simülasyonunu kendi bilgisayarınızda (RAM ve CPU sınırları dahilinde) saniyeler içinde çalıştırmanızı sağlar.

---

## 1. Yerel Geliştirme Araçları Karşılaştırması

Günümüzde geliştiricilerin kullandığı 4 temel popüler araç bulunmaktadır. Seçiminiz donanım gücünüze ve mimari ihtiyaçlarınıza göre değişir.

| Özellik / Araç | Minikube | Kind (Kubernetes in Docker) | K3d (Rancher K3s) | Docker Desktop (D.D. K8s) |
| :--- | :--- | :--- | :--- | :--- |
| **Mimari Yaklaşım** | Tek düğümlü (Single-Node) VM veya Konteyner temelli. | K8s bileşenlerini Docker konteynerleri içinde çalıştırır. | K3s'in Docker içinde çalışacak şekilde paketlenmiş ultra hafif halidir. | Docker Desktop uygulamasıyla birlikte gelen tek tuşluk entegre K8s. |
| **Çoklu Düğüm (Multi-Node)** | Destekler ancak hantaldır. | Doğal olarak destekler. CI/CD ortamları için harikadır. | Çoklu düğümü en hızlı ve en düşük RAM ile ayağa kaldıran araçtır. | Desteklemez. Tek bir node sunar. |
| **Kaynak Tüketimi (RAM/CPU)** | Görece yüksektir. | Orta seviyededir. | En düşük (En hafif) olanıdır. IoT cihazlarında bile çalışır. | Docker Desktop'ın mevcut tüketimine eklendiği için yüksektir. |
| **Öne Çıkan Özellik (Addon)** | Dashboard, Ingress gibi eklentileri (addons) tek komutla kurma (`minikube addons`). | Saf (Pure) upstream Kubernetes testleri için (CNCF uyumlu) en iyisidir. | Gelişmiş port yönlendirme ve devasa kümeleri saniyeler içinde ayağa kaldırma. | Sıfır konfigürasyon. Sadece arayüzden "Enable Kubernetes" kutucuğunu işaretlemek yeterlidir. |

---

## 2. Hangi Aracı Ne Zaman Seçmelisiniz?

### Senaryo A: "Ben Sadece Basit Bir Geliştiriciyim"

Eğer DevOps süreçleriyle işiniz yoksa, sadece yazdığınız Java veya Node.js uygulamasının Kubernetes içinde çalışıp çalışmadığını görmek istiyorsanız:
**Seçiminiz:** *Docker Desktop K8s* veya *Minikube* olmalıdır. Özellikle Minikube'un eklenti (addon) ekosistemi yeni başlayanlar için hayat kurtarıcıdır.

### Senaryo B: "Sürekli Entegrasyon (CI/CD) Boru Hatları"

Eğer GitHub Actions veya GitLab CI içinde otomatik testler koşturmak istiyorsanız, bir Sanal Makine (VM) ayağa kaldırmak çok yavaştır. Bunun yerine konteyner tabanlı bir K8s gerekir.
**Seçiminiz:** *Kind (Kubernetes in Docker)*. Doğrudan Kubernetes SIGs (Özel İlgi Grupları) tarafından geliştirilir ve resmi K8s projesinin e2e (uçtan uca) testlerinde kullanılır.

### Senaryo C: "Kapsamlı ve Hafif Çoklu Küme Mimarisi"

Eğer aynı anda 3 Worker, 2 Master node'a sahip bir kümeyi kısıtlı bir RAM ile bilgisayarınızda ayağa kaldırıp Service Mesh (Istio) ağ testleri yapacaksanız:
**Seçiminiz:** *K3d*. Arkasında endüstri standardı olan K3s (Rancher) yatar ve inanılmaz hızlı çalışır.

---

## 3. Tilt ve Skaffold ile Döngüyü Hızlandırma

Sadece yerel bir K8s kurmak yetmez. Kodunuzda yaptığınız ufacık bir değişikliği yerel Kubernetes'te görmek için şu hamallığı yapmanız gerekir:

1. Kodu kaydet.
2. `docker build` ile yeni imajı derle.
3. `docker push` ile yerel registry'ye veya Docker Hub'a at.
4. `kubectl rollout restart` ile Pod'u yenile.

Bu 4 adımlık süreci **sıfıra** indiren araçlar **Tilt** veya Google'ın geliştirdiği **Skaffold**'dur.

**Nasıl Çalışırlar?**
Siz kod dosyasında `CTRL+S` (Kaydet) tuşuna bastığınız anda, Skaffold arkaplanda saniyeler içinde imajı derler ve yerel K8s kümesindeki (Örn: Minikube) Pod'u otomatik olarak yeniler. Terminalde sanki yerel bir Node.js sunucusu (`nodemon`) çalıştırıyormuşsunuz gibi akıcı bir K8s geliştirici deneyimi (Developer Experience - DX) elde edersiniz.

---

## 4. Gelişmiş Bulut Bağlantılı Yerel Geliştirme: Telepresence ve mirrord

Kendi bilgisayarınızda (localhost) bir Kubernetes kümesi simüle etmek (Kind/K3d) harika bir yöntemdir. Ancak uygulamanız veri tabanlarına, cloud servislerine veya diğer onlarca mikroservise doğrudan bağımlıysa, tüm bu bağımlılıkları kendi bilgisayarınızda çalıştırmaya RAM ve CPU gücünüz yetmez.

Bu sorunu çözmek için **Bulut Bağlantılı Yerel Geliştirme (Cloud-Connected Local Dev)** konsepti doğmuştur. Amaç: Kodunuzu yerel makinenizde (IDE üzerinde) çalıştırırken, onun sanki uzak Kubernetes kümesindeymiş gibi ağ kurallarına erişmesini sağlamaktır.

### Telepresence (Ağ Tüneli ve Intercept)

Telepresence, uzak Kubernetes kümesi ile lokal makineniz arasında çift yönlü bir ağ tüneli kurar.

* **Nasıl Çalışır?** Uzak kümedeki podun yerine hafif bir proxy (Traffic Agent) koyar.
* **Tünelleme:** Lokal bilgisayarınızdaki tüm trafik uzak Kubernetes kümesine yönlendirilir. Lokaldeyken `curl http://database-service.default.svc.cluster.local` yazarak uzak veri tabanına doğrudan erişebilirsiniz.
* **Intercept (Trafik Yakalama):** Uzak kümedeki belirli bir servise giden HTTP isteklerini yakalayıp doğrudan sizin lokal bilgisayarınızda (örneğin port 8080'de) koşan kodunuza yönlendirir.
* **Kullanım:**

```bash
# Uzak kümeye bağlan
telepresence connect

# 'payment-service' servisine giden istekleri lokal makinedeki 8080 portuna yönlendir
telepresence intercept payment-service --port 8080:8080
```

### mirrord (Sıfır Altyapı Enjeksiyonu)

Telepresence'in aksine, uzak kümeye hiçbir agent yüklemeden veya podları bozmadan çalışan daha modern bir yaklaşımdır.

* **Nasıl Çalışır?** Sistem kancalarını (hook) kullanarak lokalde çalışan uygulamanızın sistem çağrılarını (system calls) yakalar.
* **Şeffaf Entegrasyon:** Kodunuz uzak podun ağ trafiğini, ortam değişkenlerini (Env) ve diskini doğrudan "aynalar" (mirror). Kodunuza hiçbir şey eklemeniz gerekmez.
* **Kullanım:**

```bash
# Lokalde koşan web uygulamasını, uzak podun kimliği ile çalıştır
mirrord exec --target pod/payment-service-xyz -- npm start
```

### Hangisini Seçmeli?

* **Telepresence:** Takımdaki diğer geliştiricilerin de ortak kullanabileceği, cluster içi DNS çözümlemesi ve kalıcı tünelleme gerektiren büyük kurumsal projeler için uygundur.
* **mirrord:** Cluster'a hiçbir şey kurma yetkisine (Admin yetkisine) sahip olmadığınız, sadece geçici olarak hızlıca bir podu aynalayıp lokalde debug yapmak istediğiniz durumlar için mükemmeldir.

---

## Özet

Yerel geliştirme ortamları Kubernetes'in pahalı ve ağır faturasından kurtulup hızlı test yapmamızı sağlar. Yeni başlayanlar için Docker Desktop veya Minikube ideal iken, ileri seviye ağ ve CI testleri için Kind veya K3d tercih edilmelidir. Gerçek bir Kubernetes profesyoneli, Skaffold/Tilt gibi araçlarla yerel kodlama döngüsünü (Inner Loop) otomatize ederken; karmaşık entegrasyonlarda ise Telepresence veya mirrord ile bulut gücünü lokaline taşımalıdır.
