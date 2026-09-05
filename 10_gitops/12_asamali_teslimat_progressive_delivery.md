# Aşamalı Teslimat ve A/B Test (Progressive Delivery Guide)

**Aşamalı Teslimat (Progressive Delivery)**, yeni yazılım sürümlerini (updates) tüm kullanıcılara aynı anda açmak yerine, kademeli ve kontrollü bir biçimde yayarak üretim (production) kesintisi riskini en aza indiren modern bir yayınlama metodolojisidir. Bu yöntem; Canary, Blue/Green ve A/B Testing tekniklerini otomatik metrik analizleri ve kendi kendine geri alma (self-healing/auto-rollback) mekanizmalarıyla birleştirir.

---

## 1. Mimarisi ve Temel Kavramlar

```text
Geleneksel Dağıtım (Riskli):
  [ Sürüm 1 (Trafik %100) ] ──► (Tek Seferde Değişim) ──► [ Sürüm 2 (Trafik %100) ]

Aşamalı Teslimat (Güvenli):
  [ Sürüm 1 ] ──► [ Kademeli Canary (%5 ──► %20 ──► %50) ] ──► [ Sürüm 2 ]
                        │
                        ▼ (Metrik Denetimi - Prometheus)
                     Hata Var mı? ──► Evetse ──► Otomatik Rollback!
```

Sistemde kullanılan popüler araçlar:

* **Argo Rollouts:** Argo projesinin Kubernetes-native progresif dağıtım aracı.
* **Flagger:** FluxCD ile uyumlu çalışan, NGINX Ingress ve modern **Gateway API** destekli alternatif progresif dağıtım aracı.
* **Flagsmith / LaunchDarkly:** Kod düzeyinde özellik açma/kapatmayı (Feature Flags) sağlayan SaaS araçları.

---

## 2. Argo Rollouts: Canary ve Analiz Yapılandırması

Canary stratejisinde, yeni sürümün çalışması arka planda sürekli denetlenir.

### A. Canary Adımları ve Analiz Entegrasyonu

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: payments-canary-rollout
  namespace: production
spec:
  replicas: 10
  strategy:
    canary:
      analysis:
        templates:
          - templateName: success-rate-analysis
        args:
          - name: service-name
            value: payments-canary-svc
      steps:
        - setWeight: 20
        - pause: { duration: 10m } # 10 dakika boyunca metrikleri incele
        - setWeight: 50
        - pause: { duration: 10m }
        - setWeight: 100
  template:
    spec:
      containers:
        - name: payments
          image: ghcr.io/company/payments:v3.1.0
```

### B. `AnalysisTemplate` (Başarı Oranı ve Gecikme Denetimi)

Yukarıdaki Rollout'un her adımda çalıştıracağı analiz kuralı:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-analysis
  namespace: production
spec:
  metrics:
    - name: success-rate
      interval: 1m
      successCondition: result[0] >= 0.99 # Başarı oranı %99'un altına düşerse otomatik Rollback tetikle
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus.monitoring:9090
          query: |
            sum(rate(http_requests_total{status!~"5.*"}[2m])) / sum(rate(http_requests_total[2m]))
```

---

## 3. Gelişmiş Trafik Yönlendirme (Advanced Routing)

### A. Üst Bilgi (Header) Tabanlı Yönlendirme

Belirli kullanıcıları (örneğin sadece şirket içi test ekibini) her zaman yeni sürüme (Canary) yönlendirmek için Ingress veya Service Mesh üzerinde kural kurgulanabilir:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: payments-canary-header-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-by-header: "X-Canary-User"
    nginx.ingress.kubernetes.io/canary-by-header-value: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: api.company.com
      http:
        paths:
          - path: /v1/payment
            pathType: Prefix
            backend:
              service:
                name: payments-canary-svc
                port:
                  number: 80
```

Geliştirici testi:

```bash
curl -H "X-Canary-User: true" https://api.company.com/v1/payment
```

### B. Trafik Aynalama (Traffic Mirroring / Shadow Traffic)

Yeni sürümü canlı kullanıcıları etkilemeden test etmenin en güvenli yolu **Traffic Mirroring**'dir. Istio VirtualService yardımıyla, canlı trafiğin bir kopyası arka planda sessizce Canary pod'larına gönderilir, ancak Canary'nin verdiği yanıtlar kullanıcıya iletilmez (sıfır risk):

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: payments-mirroring
  namespace: production
spec:
  hosts:
    - payments-service
  http:
    - route:
        - destination:
            host: payments-service
            subset: v1
      mirror:
        host: payments-service
        subset: v2
      mirrorPercentage:
        value: 100.0
```

---

## 4. Argo Rollouts: Blue-Green Stratejisi

Blue-Green modelinde, yeni sürüm (Green) arka planda tamamen ayağa kalktıktan sonra, ön izleme (preview) servisi üzerinden manuel test edilebilir. Onay verilince aktif (live) servis yönlendirilir:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: payment-bluegreen
  namespace: production
spec:
  replicas: 5
  strategy:
    blueGreen:
      activeService: payment-prod-svc
      previewService: payment-preview-svc
      autoPromotionEnabled: false # Manuel onay bekle
  template:
    spec:
      containers:
        - name: payment
          image: ghcr.io/company/payment:v2.0.0
```

Doğrulama ve onay komutları:

```bash
# 1. Preview (Green) ortamı test edin:
curl https://preview-api.company.com/healthz

# 2. Testler başarılı ise geçişi onaylayın (Promote):
kubectl argo rollouts promote payment-bluegreen -n production
```

---

## 5. Argo Rollouts ve Flagger Karşılaştırması

Progresif teslimat (Progressive Delivery) mimarisinde iki büyük açık kaynaklı denetleyici öne çıkmaktadır. Ekibinizin altyapısına göre doğru aracı seçmek mimari karmaşıklığı azaltır:

| Kriter | Argo Rollouts | Flagger |
| :--- | :--- | :--- |
| **Ekosistem** | ArgoCD ve Kubernetes GitOps odaklı projeler. | FluxCD ve bağımsız Kubernetes ortamları. |
| **Kaynak Türü** | Yerleşik `Deployment` yerine özel `Rollout` CRD nesnesi kullanılır. | Standart `Deployment` kaynaklarını değiştirmeden dışarıdan sarmalar. |
| **Trafik Denetleyicisi** | NGINX Ingress, ALB, Istio, SMI. | Kubernetes Gateway API, Istio, Linkerd, Contour. |
| **Otomasyon** | Prometheus, Datadog ve Wavefront analiz şablonları. | Prometheus metrikleri ve yük testi webhook entegrasyonu. |
| **İdeal Senaryo** | Sıfırdan GitOps ve Argo ekosistemi kuran ekipler. | Mevcut standart Deployment nesnelerine dokunmadan otomatik canary isteyenler. |

*(Flagger'ın Gateway API ile derinlemesine yapılandırması, yük testi webhook'ları ve adım adım canary analizi için bkz: **Bölüm 17 — Flagger ile Otomatik Canary Dağıtım**).*

---

## 6. Kod Düzeyinde Özellik Bayrakları (Feature Flags - Flagsmith)

Progresif dağıtım altyapı düzeyinde yapılırken, kod düzeyinde de **Feature Flags** (Flagsmith vb.) kullanılarak bir özellik (Örn: Yeni sepet tasarımı) deploy yapılmadan anlık olarak açılıp kapatılabilir.

### Python Flagsmith Entegrasyonu

```python
import os
from flagsmith import Flagsmith

# Flagsmith istemcisini başlatın
flagsmith_client = Flagsmith(environment_key=os.environ["FLAGSMIH_ENV_KEY"])

def process_checkout(user_id: str):
    # Kullanıcıya ait özellikleri (flags) çekin
    user_flags = flagsmith_client.get_identity_flags(user_id)

    # Özelliğin aktif olup olmadığını kontrol edin
    if user_flags.is_feature_enabled("new-payment-engine"):
        return execute_new_payment_flow(user_id) # Canary kullanıcı grubu
    else:
        return execute_legacy_payment_flow(user_id)
```

---

## 7. A/B Testing (Istio VirtualService & Cookie-Based Routing)

A/B Testing, kullanıcıları tarayıcı çerezlerine (cookie) veya HTTP başlıklarına göre belirli gruplara (A ve B grupları) bölerek iki sürümün davranışını ölçer.

### Istio Cookie Tabanlı Yönlendirme

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: store-ab-testing
  namespace: production
spec:
  hosts:
    - store.company.com
  http:
    - match:
        - headers:
            cookie:
              regex: ".*group=beta.*"
      route:
        - destination:
            host: store-service
            subset: v2
    - route:
        - destination:
            host: store-service
            subset: v1
```
