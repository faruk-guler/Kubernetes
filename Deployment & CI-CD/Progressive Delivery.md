# Progressive Delivery

Progressive Delivery, yeni yazılım sürümlerini tüm kullanıcılara aynı anda açmak yerine kontrollü biçimde yayarak riski minimize eden bir stratejidir. Canary, blue-green ve A/B testini ölçüm ve otomatik analiz ile birleştirir.

---

## Kavramlar

```
Traditional Deploy:   v1 → v2 (tüm kullanıcılar anında)
Progressive Delivery: v1 → %5 → %25 → %50 → %100 (v2)
                           ↑       ↑      ↑
                        Ölç    Ölç    Ölç → Sorun yoksa devam
```

**Araçlar:**
- **Argo Rollouts** — Kubernetes-native, Prometheus entegrasyonlu
- **Flagger** — Flux ile uyumlu, Istio/NGINX/Gateway API destekli
- **Feature flags** — LaunchDarkly, Flagsmith (kod düzeyinde)

---

## Argo Rollouts: Canary Stratejisi

Argo Rollouts, Prometheus metriklerine göre canary'nin başarılı olup olmadığına otomatik karar verir.

### Temel Canary Adımları

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api-rollout
  namespace: production
spec:
  replicas: 20
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: ghcr.io/company/api:v2.1.0
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
  strategy:
    canary:
      steps:
      - setWeight: 5          # %5 trafik canary'ye
      - pause: {duration: 2m}
      - analysis:             # Prometheus'tan ölçüm al
          templates:
          - templateName: success-rate
          - templateName: latency-p99
      - setWeight: 25
      - pause: {duration: 5m}
      - setWeight: 50
      - pause: {duration: 10m}
      - setWeight: 100        # Tam geçiş
```

### AnalysisTemplate: Başarı Oranı + Gecikme

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
  namespace: production
spec:
  metrics:
  - name: http-success-rate
    interval: 60s
    count: 5          # 5 kez ölç (= 5 dakika)
    successCondition: result[0] >= 0.99
    failureLimit: 1   # 1 başarısız → abort
    provider:
      prometheus:
        address: http://prometheus-kube-prometheus-prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{
            app="api",
            code!~"5.."
          }[2m])) /
          sum(rate(http_requests_total{
            app="api"
          }[2m]))
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency-p99
  namespace: production
spec:
  metrics:
  - name: p99-latency-ms
    interval: 60s
    count: 5
    successCondition: result[0] <= 300   # 300ms altı
    failureLimit: 1
    provider:
      prometheus:
        address: http://prometheus-kube-prometheus-prometheus.monitoring:9090
        query: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket{app="api"}[2m])) by (le)
          ) * 1000
```

### Header-Based Canary Routing

Belirli kullanıcıları (örn. internal test ekibi) her zaman canary'ye yönlendir:

```yaml
spec:
  strategy:
    canary:
      canaryMetadata:
        labels:
          track: canary
      stableMetadata:
        labels:
          track: stable
      trafficRouting:
        nginx:
          stableIngress: api-ingress
          additionalIngressAnnotations:
            canary-by-header: X-Canary-User
            canary-by-header-value: "true"
      steps:
      - setWeight: 10
      - pause: {}             # Manuel onay bekle
      - setWeight: 50
      - pause: {duration: 5m}
      - setWeight: 100
```

```bash
# Canary'yi test etmek için
curl -H "X-Canary-User: true" https://api.company.com/v1/products
```

### Traffic Mirroring (Shadow Traffic)

Canary pod'u gerçek trafiğin kopyasını alır; yanıtlar kullanıcıya dönmez. Zero-risk canary testi:

```yaml
spec:
  strategy:
    canary:
      steps:
      - experiment:
          duration: 10m
          templates:
          - name: canary-shadow
            specRef: canary
          analyses:
          - name: shadow-analysis
            templateName: shadow-success-rate
```

---

## Argo Rollouts: Blue-Green Stratejisi

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api-bluegreen
  namespace: production
spec:
  replicas: 10
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: ghcr.io/company/api:v2.1.0
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
  strategy:
    blueGreen:
      activeService: api-active       # Canlı trafik
      previewService: api-preview     # Test trafiği
      autoPromotionEnabled: false     # Manuel onay gerekli

      prePromotionAnalysis:
        templates:
        - templateName: smoke-test
        - templateName: success-rate
        args:
        - name: service-name
          value: api-preview

      postPromotionAnalysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: api-active

      scaleDownDelaySeconds: 900      # 15 dakika eski ortamı tut
```

```bash
# Preview ortamını test et
curl https://preview.api.company.com/healthz

# Onayladıktan sonra promote et
kubectl argo rollouts promote api-bluegreen -n production
```

---

## Otomatik Rollback

Analiz başarısız olduğunda Argo Rollouts otomatik olarak önceki sürüme döner:

```yaml
spec:
  strategy:
    canary:
      analysis:
        templates:
        - templateName: success-rate
        startingStep: 2    # 2. adımdan itibaren analiz başlat
        args:
        - name: service-name
          value: api-canary
      steps:
      - setWeight: 10
      - pause: {duration: 1m}
      # Analiz başlar: başarısız → otomatik abort + rollback
      - setWeight: 30
      - pause: {duration: 5m}
      - setWeight: 100
```

```bash
# Rollback durumunu izle
kubectl argo rollouts get rollout api-rollout -n production --watch

# Manuel abort (acil durum)
kubectl argo rollouts abort api-rollout -n production

# Önceki versiyona geri dön
kubectl argo rollouts undo api-rollout -n production
```

---

## Flagger: NGINX Ingress ile Otomatik Canary

```bash
helm repo add flagger https://flagger.app
helm install flagger flagger/flagger \
  --namespace ingress-nginx \
  --set meshProvider=nginx \
  --set metricsServer=http://prometheus-kube-prometheus-prometheus.monitoring:9090
```

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: web-app
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  ingress:
    refKind: Ingress
    refName: web-app-ingress
  progressDeadlineSeconds: 600
  service:
    port: 80
    targetPort: 8080
  analysis:
    interval: 1m
    threshold: 5           # 5 başarısız kontrol → rollback
    maxWeight: 50          # Max %50 canary trafiği
    stepWeight: 10         # Her adımda %10 artır
    metrics:
    - name: request-success-rate
      threshold: 99
      interval: 1m
    - name: request-duration
      threshold: 500        # ms
      interval: 1m
    webhooks:
    - name: smoke-test
      url: http://flagger-loadtester.test/
      timeout: 15s
      metadata:
        type: cmd
        cmd: "curl -s http://web-app-canary.production/healthz | grep OK"
    - name: load-test
      url: http://flagger-loadtester.test/
      timeout: 5s
      metadata:
        type: cmd
        cmd: "hey -z 1m -q 10 -c 2 http://web-app-canary.production/"
```

### Flagger + Gateway API (2026 Standardı)

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: web-app
  namespace: production
spec:
  provider: gateway
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  routeRef:
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    name: web-app
  analysis:
    interval: 1m
    threshold: 5
    maxWeight: 50
    stepWeight: 10
    metrics:
    - name: request-success-rate
      threshold: 99
      interval: 1m
```

---

## Feature Flags (Flagsmith)

Kod düzeyinde feature flag — deploy olmadan özelliği aç/kapat:

```bash
helm repo add flagsmith https://flagsmith.github.io/flagsmith-charts
helm install flagsmith flagsmith/flagsmith \
  --namespace flagsmith \
  --create-namespace \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=flagsmith.company.internal
```

```python
import os
from flagsmith import Flagsmith

client = Flagsmith(environment_key=os.environ["FLAGSMITH_KEY"])

def get_recommendation(user_id: str):
    flags = client.get_identity_flags(user_id)

    if flags.is_feature_enabled("new-recommendation-engine"):
        return new_recommendation_engine(user_id)    # Canary kullanıcılar
    else:
        return legacy_recommendation(user_id)
```

**Segment stratejisi:**

| Segment | Flag durumu | Kapsam |
|:--------|:-----------|:-------|
| internal | Açık | Tüm şirket çalışanları |
| beta | Açık | Opt-in kullanıcılar (%5) |
| all | Açık | Tam genel yayın |

---

## A/B Testing (Istio VirtualService)

```yaml
# Header'a göre kullanıcı segmentasyonu
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-ab-test
  namespace: production
spec:
  hosts:
  - api.company.com
  http:
  - match:
    - headers:
        x-user-group:
          exact: beta
    route:
    - destination:
        host: api-service
        subset: v2
      weight: 100
  - route:
    - destination:
        host: api-service
        subset: v1
      weight: 100
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-destination
  namespace: production
spec:
  host: api-service
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

### A/B Testing — Cookie Tabanlı

```yaml
spec:
  http:
  - match:
    - headers:
        cookie:
          regex: ".*experiment=v2.*"
    route:
    - destination:
        host: api-service
        subset: v2
  - route:
    - destination:
        host: api-service
        subset: v1
```

---

## Araç Seçim Rehberi

| Durum | Araç |
|:------|:-----|
| K8s-native, Prometheus ile otomatik analiz | Argo Rollouts |
| Flux tabanlı GitOps + Istio/NGINX/Gateway API | Flagger |
| Deploy olmadan özellik aç/kapat | Feature Flags (Flagsmith) |
| Header/cookie bazlı kullanıcı segmentasyonu | A/B Testing (Istio) |
| İki versiyonu aynı anda production'da karşılaştır | Argo Experiments |
| Zero-risk canary (yanıt kullanıcıya dönmez) | Traffic Mirroring |

---

## Karar Ağacı

```
Yeni özelliği yayacak mısın?
│
├── Tüm kullanıcılara hemen → Traditional Deploy (riskli)
│
├── Kontrollü trafik kaydırma
│   ├── K8s-native + Prometheus → Argo Rollouts canary
│   ├── GitOps (Flux) + Istio   → Flagger
│   └── Anlık geri alma gerekli → Blue-Green
│
├── Kullanıcı segmentasyonu
│   ├── Header/cookie bazlı     → Istio A/B Test
│   └── Kod içi açma/kapama     → Feature Flags
│
└── İki versiyon karşılaştır
    └── Gerçek trafikle          → Argo Experiment
```

---

> [!TIP]
> Canary analizi için en az 5 dakika bekleyin. `interval: 60s` × `count: 5` = 5 dakika minimum gözlem süresi. Kısa süreli trafik spike'ları yanıltıcı rollback tetikleyebilir.

> [!WARNING]
> Blue-green stratejisinde `scaleDownDelaySeconds: 900` (15 dakika) olarak ayarlayın. Sorun yaşanırsa eski ortam hâlâ ayaktadır; süratle rollback yapılabilir. Bu değeri 0 yapmak tehlikelidir.

> [!NOTE]
> Feature flags ve canary deploy birbirini tamamlar: traffic-level canary (%5 kullanıcı yeni pod'a gider), code-level flag ise o %5 içinden sadece opt-in segment için yeni kodu çalıştırır. İkisi birlikte kullanılabilir.
