# Argo Rollouts — Progressive Delivery

## 1.1 Neden Progressive Delivery?

Standart Kubernetes Deployment'ı "RollingUpdate" yapar — eski pod'ları teker teker yenileriyle değiştirir. 2026'da bu yeterince güvenli değildir.

| Yaklaşım | Risk | Açıklama |
|:---|:---:|:---|
| RollingUpdate | Yüksek | Hata fark edilene kadar tüm kullanıcılar etkiler |
| **Canary** | Düşük | %5-10 kullanıcı ile test, analiz başarılıysa genişlet |
| **Blue-Green** | Çok Düşük | İki tam ortam, tek hamle ile geçiş |

## 1.2 Kurulum

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Argo Rollouts kubectl eklentisi
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

## 1.3 Canary Deployment

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: web-app
  namespace: production
spec:
  replicas: 10
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: my-registry/web-app:v2.0.0
        ports:
        - containerPort: 8080
  strategy:
    canary:
      canaryService: web-app-canary    # Canary pod'larına giden servis
      stableService: web-app-stable    # Eski pod'lara giden servis
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:    # Gateway API entegrasyonu
            httpRoute: web-app-route
            namespace: production
      steps:
      - setWeight: 5             # %5 trafiği canary'e gönder
      - pause: {duration: 10m}   # 10 dakika bekle
      - analysis:                # Analiz yap
          templates:
          - templateName: success-rate
      - setWeight: 25
      - pause: {duration: 30m}
      - setWeight: 50
      - pause: {duration: 1h}
      - setWeight: 100           # Tam geçiş
```

## 1.4 Analiz Şablonu (Otomatik Rollback)

Prometheus metriklerine göre otomatik karar verme:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
  namespace: production
spec:
  metrics:
  - name: success-rate
    successCondition: result[0] >= 0.95     # %95'in üzerinde başarı
    failureLimit: 3
    interval: 5m
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{app="web-app",status!~"5.."}[5m])) /
          sum(rate(http_requests_total{app="web-app"}[5m]))
```

## 1.5 Blue-Green Deployment

```yaml
spec:
  strategy:
    blueGreen:
      activeService: web-app-active       # Canlı (eski) servis
      previewService: web-app-preview     # Yeni versiyon servisi
      autoPromotionEnabled: false         # Manuel onay gerekli
      scaleDownDelaySeconds: 600          # Eski pod'ları 10 dk sonra kapat
      prePromotionAnalysis:
        templates:
        - templateName: success-rate
```

## 1.6 Rollout Yönetimi

```bash
# Rollout durumu izle
kubectl argo rollouts get rollout web-app -n production --watch

# Canary'yi manuel ilerlet
kubectl argo rollouts promote web-app -n production

# Geri al
kubectl argo rollouts abort web-app -n production
kubectl argo rollouts undo web-app -n production

# Argo Rollouts Dashboard
kubectl argo rollouts dashboard
# http://localhost:3100
```

