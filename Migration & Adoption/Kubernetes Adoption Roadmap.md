# Kubernetes Benimseme Yol Haritası

Kubernetes geçişi teknik bir proje değil, organizasyonel bir dönüşümdür. Bu bölüm, "neden Kubernetes?" sorusundan production'da ilk workload'a kadar olan yolculuğu adım adım ele alır.

---

## Geçiş Öncesi: Hazırlık Değerlendirmesi

### Organizasyon Olgunluk Matrisi

```
Soru                                    | Hayır | Kısmen | Evet
----------------------------------------|-------|--------|-----
Uygulamalar containerize edildi mi?     |  0    |   1    |  2
CI/CD pipeline var mı?                  |  0    |   1    |  2
İzleme/alerting altyapısı var mı?       |  0    |   1    |  2
Infrastructure-as-Code kullanılıyor mu? |  0    |   1    |  2
Ekipte K8s deneyimi var mı?             |  0    |   1    |  2

Toplam:
0-4:  ❌ Hazır değil — önce temel altyapıyı kur
5-7:  🟡 Hazırlanma aşaması — pilot proje başlat
8-10: ✅ Hazır — üretim geçişini planla
```

---

## Geçiş Modelleri

### Model 1: Lift and Shift (Hızlı ama Riskli)
```
Mevcut uygulama → Container'a koy → K8s'e deploy et
```
- **Artı:** Hızlı, kod değişikliği yok
- **Eksi:** K8s'in avantajlarından yararlanılmaz (scaling, self-healing zayıf kalır)
- **Kimler için:** Legacy uygulamalar, kısa vadeli geçiş

### Model 2: Refactor (Önerilen)
```
Mevcut uygulama → 12-Factor prensiplerine göre yeniden yapılandır → K8s'e deploy
```
- **Artı:** K8s'in tüm özelliklerini kullanır
- **Eksi:** Zaman ve kod değişikliği gerektirir
- **Kimler için:** Uzun vadeli, yeni başlayan servisler

### Model 3: Strangler Fig (Kademeli)
```
Monolith çalışmaya devam eder
       ↓
Yeni özellikler → Mikroservis olarak K8s'e
       ↓
Monolith'ten trafik yavaşça yeni servise kayar
       ↓
Monolith küçülür, sonunda emekli olur
```
- **Artı:** Risksiz, sürekli çalışır
- **Eksi:** Uzun soluklu (12-24 ay)
- **Kimler için:** Büyük, kritik monolith uygulamalar

---

## 12-Factor App Prensipleri (K8s Uyumu)

K8s için tasarlanmış uygulama şu kriterleri karşılamalı:

| Factor | Kubernetes Karşılığı |
|:-------|:--------------------|
| **1. Codebase** | Her servis ayrı Git repo |
| **2. Dependencies** | `requirements.txt` / `go.mod` — image içinde |
| **3. Config** | ConfigMap & Secret (env'den okuma) |
| **4. Backing Services** | Service DNS üzerinden bağlan |
| **5. Build/Release/Run** | CI/CD pipeline ayrımı |
| **6. Processes** | Stateless Pod'lar |
| **7. Port Binding** | containerPort tanımı |
| **8. Concurrency** | HPA ile horizontal scaling |
| **9. Disposability** | SIGTERM handle, graceful shutdown |
| **10. Dev/Prod Parity** | Aynı image, farklı ConfigMap |
| **11. Logs** | stdout/stderr → log aggregator |
| **12. Admin Processes** | Job / CronJob |

---

## Containerization Checklist

### Uygulama Hazır mı?

```bash
# ✅ SIGTERM sinyalini handle ediyor mu?
# Uygulama graceful shutdown yapmalı

# Go örneği:
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
<-quit
server.Shutdown(context.Background())

# Python örneği:
import signal, sys
def handler(sig, frame): sys.exit(0)
signal.signal(signal.SIGTERM, handler)
```

```bash
# ✅ Health endpoint var mı?
GET /healthz    → 200 OK (liveness)
GET /readyz     → 200 OK (readiness)
GET /metrics    → Prometheus format (observability)
```

```bash
# ✅ Config environment variable'dan okunuyor mu?
# ❌ Yanlış: config.yaml dosyasından hardcoded okuma
# ✅ Doğru:
DATABASE_URL = os.environ.get("DATABASE_URL")
REDIS_HOST   = os.environ.get("REDIS_HOST", "redis:6379")
```

```bash
# ✅ Log'lar stdout/stderr'e yazılıyor mu?
# ❌ Yanlış: /var/log/app.log dosyasına yaz
# ✅ Doğru: print() / console.log() / logger.info() → stdout
```

```bash
# ✅ Stateless mi?
# ❌ Yanlış: Lokal dosya sistemi (/tmp/session-data)
# ✅ Doğru: Redis, S3, veritabanı gibi dış depolamada tut
```

---

## Aşamalı Geçiş Planı

### Faz 1: Temel (0-3 Ay)
```
✅ Lab cluster kur (k3d veya Kind)
✅ İlk uygulamayı containerize et
✅ CI/CD pipeline'ı entegre et (image build + push)
✅ Staging cluster'a deploy et
✅ Ekip K8s eğitimi al (CKA hazırlık)
```

### Faz 2: Pilot (3-6 Ay)
```
✅ 1-2 düşük riskli servis production'a taşı
✅ Observability kur (Prometheus + Grafana)
✅ GitOps uygulamaya koy (ArgoCD)
✅ Networking: Ingress + TLS
✅ Secret yönetimi: External Secrets
```

### Faz 3: Olgunlaşma (6-12 Ay)
```
✅ Güvenlik sertleştirme (NetworkPolicy, RBAC, Kyverno)
✅ Ölçeklendirme: HPA + VPA + KEDA
✅ Disaster Recovery planı (Velero)
✅ Multi-environment stratejisi (dev/staging/prod)
✅ SLO tanımlama ve error budget
```

### Faz 4: Platform (12+ Ay)
```
✅ Internal Developer Platform (Backstage)
✅ Self-service altyapı (Crossplane)
✅ FinOps: Kubecost + maliyet optimizasyonu
✅ Multi-cluster stratejisi
✅ Platform Engineering ekibi oluştur
```

---

## Yaygın Hatalar ve Önleme

| Hata | Sonuç | Önlem |
|:-----|:------|:------|
| Resources tanımlamadan deploy | Noisy neighbor, OOMKill | LimitRange ile namespace default'ları zorla |
| `latest` image tag kullanmak | Hangi version çalışıyor? bilinmiyor | Git SHA ile tag'le |
| Tek node cluster | SPOF — node düşerse her şey durur | En az 3 worker node |
| Sertifikaları unutmak | 1 yıl sonra cluster erişim yok | `kubeadm certs check-expiration` cron job |
| Backup almadan upgrade | Veri kaybı riski | Önce etcd backup, sonra upgrade |
| Tüm pod'ları root çalıştırmak | Güvenlik riski | `securityContext.runAsNonRoot: true` |
| ReadWriteMany PVC | Çoğu cloud provider desteklemez | NFS CSI veya `ReadWriteOnce` + StatefulSet |

---

## Organizasyon Dönüşümü

### Ekip Yapısı

```
Geleneksel:
  Dev Ekibi → Ops Ekibi → Prod
  (silos, el ile geçiş)

K8s ile DevOps:
  Dev + Ops birlikte → CI/CD → Prod
  (ortak sorumluluk)

Platform Engineering (olgun):
  Platform Ekibi → Golden paths → Geliştiriciler self-serve
  (ölçeklenebilir)
```

### Gerekli Beceriler

```
Birinci Yıl:
  ├── Container (Docker) temelleri
  ├── kubectl komutları
  ├── YAML yazımı
  └── CI/CD entegrasyonu

İkinci Yıl:
  ├── K8s networking (CNI, Service, Ingress)
  ├── Security (RBAC, NetworkPolicy)
  ├── Observability (Prometheus, Grafana)
  └── GitOps (ArgoCD/Flux)

Platform Mühendisi:
  ├── Cluster yönetimi (Cluster API, kubeadm)
  ├── Operator geliştirme (Kubebuilder)
  ├── Multi-cluster stratejisi
  └── FinOps ve kapasite planlama
```
