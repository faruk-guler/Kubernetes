# Kubernetes Adaptasyon ve Geçiş Yol Haritası

Kubernetes'e geçiş, sadece teknik bir araç değişimi değil; organizasyonel, mimari ve kültürel bir dönüşüm sürecidir. Bu rehber, bir organizasyonun "Kubernetes'e ihtiyacımız var mı?" sorusundan başlayıp üretim ortamında (production) olgun bir platform işletmeye kadar uzanan yolculuğunu adım adım planlar.

---

## 1. Geçiş Öncesi Değerlendirme (Organizasyonel Olgunluk)

Kubernetes kurmadan önce organizasyonunuzun bu teknolojiye hazır olup olmadığını değerlendirin:

```
[ HAZIRLIK OLUNLUK MATRİSİ ]

Soru Kriterleri                             | Hayır | Kısmen | Evet
────────────────────────────────────────────┼───────┼────────┼──────
1. Uygulamalar konteynerize edildi mi?      |   0   |   1    |   2
2. Aktif bir CI/CD boru hattı var mı?       |   0   |   1    |   2
3. Merkezi izleme/loglama altyapısı var mı? |   0   |   1    |   2
4. Altyapı kodla (IaC - Terraform) yönetilir mi?|   0   |   1    |   2
5. Ekipte Kubernetes deneyimi var mı?        |   0   |   1    |   2

Değerlendirme Puanı:
  0 - 4  Puan: ❌ Hazır Değil (Önce konteyner ve CI/CD temellerini kurun)
  5 - 7  Puan: 🟡 Hazırlık Aşaması (Pilot bir proje ile test edin)
  8 - 10 Puan: ✅ Tamamen Hazır (Üretim ortamı geçiş planını başlatın)
```

---

## 2. Kubernetes Geçiş Modelleri

Uygulamalarınızı Kubernetes'e taşımak için üç temel strateji mevcuttur:

```
1. LIFT & SHIFT (Doğrudan Taşıma):
   Uygulama ──► Konteyner İmajı Yap ──► K8s'e Deploy Et (Hızlı, Kod Değişimi Yok, Verimsiz)

2. REFACTOR (Yeniden Yapılandırma):
   Uygulama ──► 12-Factor Prensiplerine Uygun Hale Get ──► K8s'e Deploy Et (Önerilen, Verimli)

3. STRANGLER FIG (Kademeli Dönüşüm):
   Monolith Çalışır ──► Yeni Özellikleri Mikroservis Yap ──► Trafiği Kademeli Kaydır (En Güvenli)
```

---

## 3. Bulut-Yerli (Cloud-Native) Uygulama Prensipleri: 12-Factor App

Kubernetes üzerinde stabil ve ölçeklenebilir çalışan uygulamalar **12-Factor App** prensiplerine uygun tasarlanmalıdır:

| Prensip (Factor) | Kubernetes Karşılığı ve Uygulanışı |
| :--- | :--- |
| **1. Codebase (Kod Tabanı)** | Her mikroservis kendi bağımsız Git deposunda barındırılır. |
| **2. Dependencies (Bağımlılıklar)**| Tüm bağımlılıklar imaj derleme aşamasında konteynerin içine gömülür. |
| **3. Config (Yapılandırma)** | Uygulama ayarları kodun içinden ayrılır; **ConfigMap** ve **Secret** ile enjekte edilir. |
| **4. Backing Services (Destek Servisleri)**| Veritabanı ve cache gibi servisler küme içi DNS adresleri üzerinden bağlanır. |
| **5. Build, Release, Run** | Derleme, sürümleme ve çalıştırma aşamaları CI/CD araçları ile net olarak ayrılır. |
| **6. Processes (İşlemler)** | Podlar **stateless** (durumsuz) tasarlanır. State (durum) verisi dış sistemlerde tutulur. |
| **7. Port Binding (Port Eşleme)** | Uygulama kendi portunu dışa açar, Kubernetes Service bunu hedef porta yönlendirir. |
| **8. Concurrency (Eşzamanlılık)** | Ölçekleme, podların içindeki thread sayısıyla değil, pod kopyaları (replicas) artırılarak yapılır (HPA). |
| **9. Disposability (Kullanılabilirlik)**| Podlar hızlı başlayıp hızlı durabilmelidir. Kapatma sırasında **SIGTERM** sinyali yakalanmalı ve graceful shutdown uygulanmalıdır. |
| **10. Dev/Prod Parity** | Geliştirme (dev) ve üretim (prod) ortamları aynı imajı kullanır, sadece ortam değişkenleri değişir. |
| **11. Logs (Günlükler)** | Uygulama logları diske yazmaz; `stdout` ve `stderr` akışlarına yazar, aracı yazılımlar (Loki/Fluent Bit) toplar. |
| **12. Admin Processes** | Veritabanı göçleri (migrations) veya periyodik işler **Job** veya **CronJob** olarak koşturulur. |

---

## 4. Konteynerleştirme ve K8s Hazırlık Kontrol Listesi

Uygulamanızın Kubernetes ile uyumlu olması için şu kod standartlarını uygulayın:

### A. SIGTERM ve Graceful Shutdown Yönetimi (Go Örneği)

Kubernetes bir podu kapatmak istediğinde konteynere `SIGTERM` sinyali gönderir. Uygulama mevcut istekleri tamamlayıp kapatılmalıdır:

```go
package main

import (
 "context"
 "net/http"
 "os"
 "os/signal"
 "syscall"
 "time"
)

func main() {
 server := &http.Server{Addr: ":8080"}

 go func() {
  server.ListenAndServe()
 }()

 // Sinyalleri dinle
 quit := make(chan os.Signal, 1)
 signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
 <-quit

 // Graceful shutdown süresi (Örn: 10 saniye boyunca açık bağlantıları tamamla)
 ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
 defer cancel()
 server.Shutdown(ctx)
}
```

### B. Sağlık Kontrolü (Health Checks)

Uygulamanızda `/healthz` (Liveness) ve `/readyz` (Readiness) uç noktalarını hazırlayın ve bunları Kubernetes probe tanımlarında kullanın.

---

## 5. Dört Aşamalı Geçiş Yol Haritası (Timeline)

### 1. Aşama: Temeller (0 - 3 Ay)

* Ekibin konteynerizasyon ve Docker temellerini öğrenmesi.
* Yerel geliştirme ortamlarında testler yapılması (`k3d`, `kind`).
* İlk uygulamanın Dockerfile'ının yazılması ve CI/CD imaj derleme aşamalarının kurulması.
* CKA (Certified Kubernetes Administrator) eğitimi ve sertifikasyon süreçlerinin başlatılması.

### 2. Aşama: Pilot Dağıtımlar (3 - 6 Ay)

* Düşük riskli 1-2 servisin (Örn: frontend veya statik siteler) staging ve ardından production kümesine taşınması.
* Merkezi gözlemlenebilirlik (Prometheus + Grafana) sisteminin kurulması.
* GitOps prensiplerinin (ArgoCD veya Flux v2) hayata geçirilmesi.
* Ingress ve otomatik TLS (Cert-Manager) entegrasyonu.

### 3. Aşama: Altyapı Sertleştirme ve Güvenlik (6 - 12 Ay)

* Sıkılaştırılmış ağ politikalarının (Network Policies) ve RBAC yetkilendirmelerinin uygulanması.
* Kyverno veya OPA ile küme içi standartların denetlenmesi.
* Gelişmiş otomatik ölçeklendirme (HPA, VPA, KEDA ve Karpenter) entegrasyonu.
* Velero ile Disaster Recovery ve etcd yedekleme testlerinin tamamlanması.

### 4. Aşama: Platform Mühendisliği (12+ Ay)

* Yazılım geliştiriciler için self-servis platform portalının (Backstage IDP) kurulması.
* Crossplane ile bulut kaynaklarının (RDS, S3 vb.) Kubernetes üzerinden yönetilmesi.
* Kubecost ile FinOps ve maliyet optimizasyonu analizlerinin başlatılması.
* Çoklu küme (Multi-Cluster) federasyonu ve yönetimine geçiş.
