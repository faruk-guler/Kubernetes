# Kubernetes Nedir?

Bir önceki bölümde mikroservis mimarisine geçişin nasıl bir orkestrasyon kaosuna yol açtığını gördük. Yüzlerce, belki binlerce konteynerin nerede çalışacağı, çöktüğünde ne olacağı ve birbirleriyle nasıl iletişim kuracağı gibi devasa problemleri çözmek için endüstri standardı haline gelen o "orkestra şefi" ile tanışma vakti: **Kubernetes**.

Kısaca **K8s** olarak da bilinen Kubernetes (K ve s arasında 8 harf olduğu için bu kısaltma kullanılır), Yunanca "Dümenci" veya "Pilot" anlamına gelir. Logosu da gemi dümenidir. Docker konteynerlerinizi okyanusta yüzen konteyner gemileri olarak düşünürseniz, Kubernetes bu filoyu rotasında tutan ve yöneten dümencidir.

---

## 1. Dağıtım Çağlarının Evrimi

Neden Kubernetes'e ihtiyaç duyduğumuzu anlamak için geçmişten günümüze sunucu altyapılarının evrimine bakmalıyız:

### 1.1. Geleneksel Dağıtım Çağı (Traditional Deployment)

Erken dönemlerde kuruluşlar, uygulamaları doğrudan fiziksel sunucular (bare-metal) üzerinde çalıştırıyordu. Bu yaklaşımda bir fiziksel sunucu üzerinde birden fazla uygulama çalıştığında kaynak paylaşımı sınırları (resource boundaries) çizilemezdi. Bir uygulama tüm RAM'i tükettiğinde diğer uygulamalar çökerdi. Çözüm olarak her uygulama için yeni bir fiziksel sunucu almak çok maliyetliydi.

### 1.2. Sanallaştırılmış Dağıtım Çağı (Virtualized Deployment)

Çözüm olarak VMware, Hyper-V gibi Hypervisor teknolojileri devreye girdi. Fiziksel bir sunucu üzerinde birden fazla Sanal Makine (VM - Virtual Machine) çalıştırılmaya başlandı. Her VM kendi tam teşekküllü İşletim Sistemine (OS) sahipti. Kaynaklar izoleydi, ancak her VM için devasa işletim sistemleri yüklemek ciddi CPU ve Disk israfına yol açıyordu.

### 1.3. Konteyner Dağıtım Çağı (Container Deployment)

Konteynerler, VM'lere benzer ancak izolasyon özellikleri zayıflatılarak İşletim Sistemi çekirdeğini (Kernel) ortak kullanacak şekilde hafifletilmişlerdir. Konteynerler kendi dosya sistemlerine, CPU paylarına ve belleklerine sahiptir ancak kendi işletim sistemlerini taşımazlar. Bu sayede milisaniyeler içinde açılır ve çok daha az kaynak tüketirler.

İşte binlerce hafif konteynerin devasa fiziksel veya sanal sunucu çiftlikleri (clusters) üzerine nasıl dağıtılacağı sorusu, **Konteyner Orkestrasyonu** kavramını, yani Kubernetes'i doğurdu.

---

## 2. Tarihçe ve CNCF (Cloud Native Computing Foundation)

Kubernetes gökten zembille inmemiştir; Google'ın 15 yıllık üretim (production) tecrübesinin açık kaynaklı bir meyvesidir.

### 2.1. Google Borg ve Omega'dan K8s'e

Google, arama motoru ve Gmail gibi devasa servisleri için haftalık milyarlarca konteyner çalıştırıyordu. Bu işlemleri yöneten dâhili sistemlerinin adı **Borg** ve daha sonra geliştirilen **Omega** idi. Google mühendisleri (Joe Beda, Brendan Burns, Craig McLuckie), Borg'dan elde ettikleri eşsiz tecrübeyle sistemi sıfırdan Go diliyle tekrar yazdılar ve 2014 yılında "Kubernetes" adıyla açık kaynak olarak dünyayla paylaştılar.

### 2.2. CNCF: Bulut Bilişimin Kalbi

Google, Kubernetes'i açık kaynak yaptıktan sonra mülkiyetini Linux Foundation altında kurulan **CNCF (Cloud Native Computing Foundation)** adlı vakfa devretti. CNCF, sadece Kubernetes'i değil, onun etrafında oluşan devasa ekosistemi de yönetir.

**CNCF Proje Olgunluk Seviyeleri:**

- **Sandbox (Kum Havuzu):** Deneysel, yolun başındaki projeler.
- **Incubating (Kuluçka):** Şirketlerin yavaş yavaş production'da kullanmaya başladığı büyüyen projeler.
- **Graduated (Mezun):** Kubernetes, Prometheus, Helm, Envoy gibi rüştünü ispatlamış, güvenilir endüstri standartları.

---

## 3. Kubernetes Bize Ne Vaat Eder?

Kubernetes sihirli bir değnek sunmaz, ancak donanım kümelerinizi tek bir devasa bilgisayarmış gibi yönetmenizi sağlayarak şu güçleri sunar:

### A. Otomasyon ve Kendi Kendini İyileştirme (Self-Healing)

Kubernetes'e sadece **neyi istediğinizi (Desired State)** söylersiniz (Bildirimsel / Declarative Yaklaşım). Örneğin: *"Benim API uygulamamdan her an 3 kopya (replica) çalışsın."*
Eğer sunuculardan biri alev alır veya bir konteyner CrashLoopBackOff hatasına düşerse, Kubernetes bunu anında fark eder ve ölen kopyanın yerine saniyeler içinde başka bir sunucuda yenisini ayağa kaldırır.

### B. Otomatik Ölçeklenebilirlik (Scalability)

CPU veya Bellek kullanımı arttığında, Kubernetes saniyeler içinde konteyner sayınızı yatay olarak (Horizontal Scaling) 3'ten 30'a çıkarabilir. Ayrıca, kümedeki kaynaklar yetmediğinde bulut sağlayıcınızla konuşup kümeye yeni fiziksel sunucular ekleyebilir (Cluster Autoscaler/Karpenter). Trafik azaldığında ise gereksiz sunucuları kapatarak maliyet tasarrufu (FinOps) sağlar.

### C. Altyapıdan Bağımsızlık (Vendor Agnostic & Portability)

Kubernetes, kullandığınız altyapıyı "soyutlar" (abstraction). Uygulamanız altta AWS (EKS), Google Cloud (GKE), Azure (AKS) mu yoksa kendi ofisinizdeki Bare-Metal bir sunucuda mı çalışıyor umursamaz. Bu sizi tek bir bulut sağlayıcıya finansal ve teknolojik olarak bağımlı (Vendor Lock-in) olmaktan kurtarır.

### D. Servis Keşfi ve Yük Dengeleme (Service Discovery & Load Balancing)

Konteynerlerin IP adresleri sürekli değişir. Kubernetes, konteynerlerin önüne sanal ve sabit bir IP / DNS ismi (Service) koyarak gelen trafiği arkada çalışan yüzlerce konteyner arasında eşit şekilde dağıtır.

---

## Özet

Kubernetes, Google'ın devasa ölçekteki bilgi birikiminin CNCF vakfı aracılığıyla herkese ücretsiz sunulmuş halidir. Otomasyon, ölçeklenme ve taşınabilirlik vaatleriyle modern bulut tabanlı yazılım geliştirmenin (Cloud-Native) "Evrensel İşletim Sistemi" haline gelmiştir.

Peki bu dümenci, bu kadar karmaşık bir filoyu altta yatan hangi mimari bileşenlerle yönetiyor? Bir sonraki bölümde Kubernetes'in kalbine (Control Plane ve Worker Node mimarisine) iniyoruz.
