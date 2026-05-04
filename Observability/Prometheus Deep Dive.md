# Prometheus Deep Dive

Prometheus, Kubernetes ekosisteminin de facto metrik sistemidir. Pull-based mimarisi, güçlü sorgu dili (PromQL) ve yerel alerting desteği ile 2026'da hâlâ merkezde yer alır.

---

## Mimari

```
[Kubernetes Pod'ları]
   /metrics endpoint'i açar (HTTP)
         │
         ▼
[Prometheus Server]
   Scrape (çeker) → TSDB'ye yazar (time-series)
         │
         ├── [Alertmanager] → Slack/PagerDuty/Email
         └── [Grafana]      → Görselleştirme
```

Prometheus, metrik **push** etmeyi beklemez — **pull** eder. Her target'ın `/metrics` endpoint'ini düzenli aralıklarla çeker.

---

## kube-prometheus-stack (2026 Standardı)

Prometheus, Grafana, Alertmanager ve tüm Kubernetes exporter'larını tek Helm chart ile kurar.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="SecurePass2026!" \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=10Gi
```

### Kurulu Bileşenler

```bash
kubectl get pods -n monitoring
# prometheus-prometheus-kube-prometheus-prometheus-0   ← Prometheus
# alertmanager-prometheus-kube-prometheus-alertmanager-0  ← Alertmanager
# prometheus-grafana-<hash>                            ← Grafana
# prometheus-kube-prometheus-operator-<hash>          ← Operator
# prometheus-kube-state-metrics-<hash>                ← K8s state metrikleri
# prometheus-prometheus-node-exporter-<hash>          ← Node metrikleri (DaemonSet)
```

---

## ServiceMonitor & PodMonitor

Prometheus Operator, hangi target'ların scrape edileceğini CRD'ler üzerinden yönetir.

```yaml
# Kendi uygulamanızı Prometheus'a tanıtın
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: production
  labels:
    release: prometheus    # kube-prometheus-stack selector'ı
spec:
  selector:
    matchLabels:
      app: my-app          # Hangi Service'i izle
  namespaceSelector:
    matchNames:
    - production
  endpoints:
  - port: http-metrics     # Service port adı
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

```yaml
# Pod'ları doğrudan izle (Service gerektirmez)
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: my-app-pods
  namespace: production
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: my-app
  podMetricsEndpoints:
  - port: metrics
    path: /metrics
    interval: 15s
```

---

## PromQL — Sorgu Dili

### Temel Kavramlar

```promql
# Anlık değer (gauge)
container_memory_usage_bytes

# Sayaç (counter) — rate ile kullan
rate(http_requests_total[5m])    # 5 dakikalık ortalama istek/saniye

# Histogram — quantile ile kullan
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

### Kritik Kubernetes Metrikleri

```promql
# === POD / CONTAINER ===
# CPU kullanımı (core cinsinden)
rate(container_cpu_usage_seconds_total{container!=""}[5m])

# Bellek kullanımı vs limit
container_memory_usage_bytes / container_spec_memory_limit_bytes

# Restart sayısı (CrashLoop tespiti)
increase(kube_pod_container_status_restarts_total[1h]) > 3

# === NODE ===
# Node CPU yükü
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (node)

# Node bellek kullanım yüzdesi
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# Node disk doluluk oranı
1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)

# === NETWORK ===
# Pod network çıkış trafiği (MB/s)
rate(container_network_transmit_bytes_total[5m]) / 1024 / 1024

# === ETCd ===
# etcd disk yazma gecikmesi (ms)
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) * 1000

# === API SERVER ===
# API Server istek gecikmesi
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m]))

# API Server hata oranı
rate(apiserver_request_total{code=~"5.."}[5m]) / rate(apiserver_request_total[5m])
```

### Aggregation (Gruplama)

```promql
# Namespace bazında toplam CPU
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)

# Deployment bazında pod sayısı
count(kube_pod_info) by (namespace, created_by_name)

# En çok bellek tüketen 10 container
topk(10, container_memory_usage_bytes{container!=""})

# Her node'un toplam pod sayısı
count(kube_pod_info) by (node)
```

---

## Recording Rules (Performans)

Ağır PromQL sorgularını önceden hesaplayıp saklayın:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: recording-rules
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
  - name: kubernetes.recording
    interval: 30s
    rules:
    # CPU kullanımını namespace bazında hesapla, kaydet
    - record: namespace:container_cpu_usage_seconds_total:sum_rate
      expr: |
        sum(rate(container_cpu_usage_seconds_total{
          job="kubelet", metrics_path="/metrics/cadvisor",
          container!="", image!=""
        }[5m])) by (namespace)

    # Bellek kullanımını namespace bazında hesapla
    - record: namespace:container_memory_rss:sum
      expr: |
        sum(container_memory_rss{
          job="kubelet", metrics_path="/metrics/cadvisor",
          container!=""
        }) by (namespace)
```

---

## Prometheus Federation

Çoklu cluster veya büyük ortamlarda Prometheus hiyerarşisi:

```yaml
# Global Prometheus — diğer Prometheus'lardan metrik çeker
scrape_configs:
- job_name: 'federate'
  honor_labels: true
  metrics_path: '/federate'
  params:
    match[]:
    - '{job="kubernetes-pods"}'
    - '{__name__=~"job:.*"}'
  static_configs:
  - targets:
    - 'prometheus-cluster-eu:9090'
    - 'prometheus-cluster-asia:9090'
```

---

## Prometheus Yönetimi

```bash
# Prometheus UI'a eriş
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090

# Alertmanager UI
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager -n monitoring 9093:9093

# Prometheus yapılandırmasını yeniden yükle (hot reload)
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload

# Target'ların durumu
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# TSDB istatistikleri
curl http://localhost:9090/api/v1/status/tsdb | jq '.data.headStats'
```

> [!TIP]
> Production'da Prometheus verilerini uzun süreli saklamak için **Thanos** veya **Grafana Mimir** kullanın. Prometheus'un varsayılan TSDB'si 30 günden uzun süre için tasarlanmamıştır.
