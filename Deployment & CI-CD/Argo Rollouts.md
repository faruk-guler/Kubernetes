# Argo Rollouts — Derinlemesine Rehber

Argo Rollouts'un temel canary ve blue-green stratejileri `Progressive Delivery.md`'de anlatılmaktadır. Bu dokümanda Argo Rollouts'a özgü ileri seviye özellikler ele alınır.

---

## Kurulum

```bash
# Helm ile (önerilen)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace \
  --set dashboard.enabled=true \
  --set notifications.enabled=true

# kubectl plugin
kubectl krew install argo-rollouts
kubectl argo rollouts version
```

---

## Mevcut Deployment'ı Rollout'a Dönüştürme

```yaml
# WorkloadRef — mevcut Deployment'ı silmeden Rollout'a bağla
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api-rollout
  namespace: production
spec:
  workloadRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api               # Mevcut Deployment referansı
  replicas: 10
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 5m}
      - setWeight: 100
```

```bash
# Deployment'ın replica'sını 0'a indirip kontrolü Rollout'a ver
kubectl scale deployment api --replicas=0 -n production
# Rollout devralır
```

---

## Experiment — Paralel Versiyon Karşılaştırması

Aynı anda birden fazla versiyonu gerçek trafik üzerinde test et:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Experiment
metadata:
  name: api-version-comparison
  namespace: production
spec:
  duration: 30m    # 30 dakika çalışır, sonra siler

  templates:
  - name: v2-candidate
    replicas: 2
    spec:
      containers:
      - name: api
        image: ghcr.io/company/api:v2.0.0
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"

  - name: v3-candidate
    replicas: 2
    spec:
      containers:
      - name: api
        image: ghcr.io/company/api:v3.0.0
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"

  analyses:
  - name: compare-versions
    templateName: compare-success-rate
    args:
    - name: v2-service
      value: api-v2-candidate
    - name: v3-service
      value: api-v3-candidate
```

```yaml
# Karşılaştırma için AnalysisTemplate
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: compare-success-rate
  namespace: production
spec:
  args:
  - name: v2-service
  - name: v3-service
  metrics:
  - name: v2-rate
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{service="{{args.v2-service}}",code!~"5.."}[5m]))
          / sum(rate(http_requests_total{service="{{args.v2-service}}"}[5m]))
    successCondition: result[0] >= 0.99
  - name: v3-rate
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{service="{{args.v3-service}}",code!~"5.."}[5m]))
          / sum(rate(http_requests_total{service="{{args.v3-service}}"}[5m]))
    successCondition: result[0] >= 0.99
```

---

## Çoklu Analysis Kaynağı

```yaml
# Prometheus + Datadog + Web (smoke test) birlikte
spec:
  metrics:
  # Prometheus
  - name: success-rate
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{app="api",code!~"5.."}[5m]))
          / sum(rate(http_requests_total{app="api"}[5m]))
    successCondition: result[0] >= 0.99
    interval: 60s
    count: 5

  # Web hook (smoke test / synthetic monitoring)
  - name: smoke-test
    provider:
      web:
        url: "https://api.company.com/healthz"
        timeoutSeconds: 10
        jsonPath: "{$.status}"
    successCondition: result == "ok"
    interval: 30s
    count: 3

  # Job tabanlı test
  - name: integration-test
    provider:
      job:
        spec:
          template:
            spec:
              containers:
              - name: test
                image: company/integration-tests:1.0.0
                command: ["/test", "--env=canary"]
              restartPolicy: Never
```

---

## Pre/Post Promotion Analysis (Blue-Green)

```yaml
spec:
  strategy:
    blueGreen:
      activeService: api-active
      previewService: api-preview
      autoPromotionEnabled: false

      # Promotion öncesi analiz
      prePromotionAnalysis:
        templates:
        - templateName: smoke-test
        - templateName: load-test
        args:
        - name: service-name
          value: api-preview

      # Promotion sonrası analiz (aktif trafikteyken)
      postPromotionAnalysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: api-active

      scaleDownDelaySeconds: 900    # 15 dakika eski ortamı tut
```

---

## Bildirimler (Notification)

```yaml
# ConfigMap: notification template'leri
apiVersion: v1
kind: ConfigMap
metadata:
  name: argo-rollouts-notification-cm
  namespace: argo-rollouts
data:
  # Slack bildirimi
  template.rollout-completed: |
    slack:
      attachments: |
        [{
          "color": "good",
          "title": "✅ Rollout Tamamlandı: {{.rollout.metadata.name}}",
          "text": "Namespace: {{.rollout.metadata.namespace}}\nImage: {{(index .rollout.spec.template.spec.containers 0).image}}"
        }]

  template.rollout-aborted: |
    slack:
      attachments: |
        [{
          "color": "danger",
          "title": "❌ Rollout İptal Edildi: {{.rollout.metadata.name}}",
          "text": "Otomatik rollback yapıldı!"
        }]

  # Trigger tanımları
  trigger.on-rollout-completed: |
    - send: [rollout-completed]
  trigger.on-rollout-aborted: |
    - send: [rollout-aborted]
```

```yaml
# Rollout'a bildirim annotation'ları
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-rollout-completed.slack: "deployments"
    notifications.argoproj.io/subscribe.on-rollout-aborted.slack: "deployments-alerts"
```

---

## ArgoCD Entegrasyonu

```yaml
# ArgoCD Application ile Argo Rollouts birlikte
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/company/k8s-manifests
    path: apps/api
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    # Rollout tamamlanana kadar sağlıklı kabul etme
    retry:
      limit: 5
```

```bash
# ArgoCD health check — Rollout tamamlanana kadar yeşil değil
# ArgoCD, Argo Rollouts durumunu otomatik tanır

# Git push → ArgoCD sync → Rollout başlar
# Canary adımları tamamlanana kadar ArgoCD "Progressing" gösterir
```

---

## Rollout Yönetim Komutları

```bash
# Tüm rollout'ları listele
kubectl argo rollouts list rollouts -n production

# Detaylı durum (adımlar, analiz, trafik ağırlığı)
kubectl argo rollouts get rollout api-rollout -n production --watch

# Bir sonraki adıma geç (pause'dan çık)
kubectl argo rollouts promote api-rollout -n production

# Tüm adımları atla — direkt %100
kubectl argo rollouts promote api-rollout -n production --full

# Rollback (abort + undo)
kubectl argo rollouts abort api-rollout -n production
kubectl argo rollouts undo api-rollout -n production

# Rollout'u dondur (acil durum)
kubectl argo rollouts pause api-rollout -n production

# Dashboard (tarayıcıda aç)
kubectl argo rollouts dashboard -n production
# http://localhost:3100
```

> [!TIP]
> Experiment, iki farklı versiyon arasında gerçek trafik üzerinde karşılaştırma yapmak için idealdir — "v2 mi daha hızlı, v3 mü?" sorusuna production verisiyle cevap verir.

> [!NOTE]
> Argo Rollouts + ArgoCD birlikte kullanıldığında GitOps iş akışı şöyle çalışır: image tag değişir → ArgoCD algılar → sync eder → Rollout başlar → adımlar tamamlanır → ArgoCD "Healthy" yapar. Her adım Git'te kayıt altında.
