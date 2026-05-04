# Prometheus Operator & CRD'leri

Prometheus'u elle yönetmek 2026'da anti-pattern'dir. **Prometheus Operator**, Prometheus stack'ini Kubernetes native CRD'lerle yönetir — sıfır downtime ile scrape config güncellenir.

---

## Kurulum (kube-prometheus-stack)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.retentionSize=50GB \
  --set grafana.adminPassword=changeme

# CRD'leri listele
kubectl get crd | grep monitoring.coreos.com
```

---

## ServiceMonitor — Service Bazlı Scraping

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api-monitor
  namespace: production
  labels:
    release: kube-prometheus-stack    # Prometheus selector ile eşleşmeli
spec:
  selector:
    matchLabels:
      app: api-server
  namespaceSelector:
    matchNames: [production, staging]
  endpoints:
  - port: metrics          # Service port adı
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
```

```yaml
# Uygulama Service — "metrics" port adı zorunlu
apiVersion: v1
kind: Service
metadata:
  name: api-server
  labels:
    app: api-server
spec:
  ports:
  - name: http
    port: 80
  - name: metrics         # ServiceMonitor bu isme bakıyor
    port: 9090
```

---

## PodMonitor — Pod Bazlı Scraping

Service olmadan doğrudan pod scrape'i. DaemonSet ve operatörsüz bileşenler için:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: worker-pods
  namespace: production
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: celery-worker
  podMetricsEndpoints:
  - port: metrics
    interval: 30s
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_name]
      targetLabel: pod
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
```

---

## PrometheusRule — Alert & Recording Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-rules
  namespace: production
  labels:
    release: kube-prometheus-stack    # Bu label zorunlu!
spec:
  groups:
  - name: api.availability
    rules:
    # Recording rule — önceden hesapla
    - record: job:http_requests:rate5m
      expr: sum(rate(http_requests_total[5m])) by (job, namespace)

    # Alert — yüksek hata oranı
    - alert: HighErrorRate
      expr: |
        sum(rate(http_requests_total{code=~"5.."}[5m])) by (service)
        / sum(rate(http_requests_total[5m])) by (service) > 0.05
      for: 5m
      labels:
        severity: warning
        team: backend
      annotations:
        summary: "{{ $labels.service }} hata oranı yüksek"
        description: "Son 5 dakikada %{{ $value | humanizePercentage }} hata"
        runbook: "https://wiki.company.com/runbooks/high-error-rate"

  - name: api.latency
    rules:
    - alert: HighP99Latency
      expr: |
        histogram_quantile(0.99,
          sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
        ) > 1.0
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "{{ $labels.service }} P99 latency 1s üzerinde"
```

---

## AlertmanagerConfig — Bildirim Yönlendirme

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: production-alerts
  namespace: production
spec:
  route:
    receiver: slack-production
    groupBy: [alertname, service]
    groupWait: 30s
    repeatInterval: 4h
    routes:
    - matchers:
      - name: severity
        value: critical
      receiver: pagerduty-oncall

  receivers:
  - name: slack-production
    slackConfigs:
    - channel: "#alerts-production"
      apiURL:
        name: slack-webhook-secret
        key: webhook-url
      title: '{{ template "slack.default.title" . }}'

  - name: pagerduty-oncall
    pagerdutyConfigs:
    - routingKey:
        name: pagerduty-secret
        key: routing-key
```

---

## Prometheus CR — HA Yapılandırması

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 2                          # HA
  version: v2.54.0
  serviceMonitorNamespaceSelector: {}  # Tüm namespace'ler
  serviceMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack
  ruleSelector:
    matchLabels:
      release: kube-prometheus-stack
  retention: 30d
  retentionSize: 50GB
  remoteWrite:
  - url: http://mimir-distributor.monitoring:8080/api/v1/push
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: gp3-encrypted
        resources:
          requests:
            storage: 100Gi
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 2
      memory: 8Gi
```

---

## Hızlı Debug

```bash
# Aktif ServiceMonitor'lar
kubectl get servicemonitor -A

# Prometheus hedefleri kontrol
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# http://localhost:9090/targets  →  DOWN olan hedefleri incele
# http://localhost:9090/rules    →  Alert/recording rules

# Yaygın hata: label uyumsuzluğu
kubectl describe servicemonitor api-monitor -n production
# selector ve namespaceSelector label'larını kontrol et

# Prometheus logları
kubectl logs -n monitoring prometheus-prometheus-0 -c prometheus --tail=50
```

> [!TIP]
> En yaygın hata: ServiceMonitor'daki `labels.release` değeri, Prometheus CR'daki `serviceMonitorSelector.matchLabels.release` ile eşleşmiyor. Her iki taraftaki label'ı kontrol edin.
