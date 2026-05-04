# Loki — Log Aggregation Deep Dive

Grafana Loki, Kubernetes log'larını toplamak için Prometheus ile aynı felsefede tasarlanmıştır: indeksleme yerine **label tabanlı** yaklaşım, düşük maliyet, yüksek ölçeklenebilirlik.

---

## Mimari

```
[Pod'lar — stdout/stderr]
         │
[Promtail / Fluent Bit] ← DaemonSet (her node'da)
         │  Log satırlarını topla + etiketle
         ▼
[Loki]
  ├── Distributor   → Yazma noktası, gelen log'ları dağıt
  ├── Ingester      → Bellekte tut, periyodik flush
  ├── Compactor     → Blokleri sıkıştır, eski log'ları sil
  ├── Querier       → Okuma, LogQL çalıştır
  └── Object Store  → S3/GCS/MinIO (kalıcı depolama)
         │
[Grafana] ← LogQL ile sorgula
```

---

## Kurulum (Loki Stack)

```bash
helm repo add grafana https://grafana.github.io/helm-charts

# Basit kurulum (monolithic, test için)
helm install loki grafana/loki \
  --namespace monitoring \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem

# Production (distributed, S3)
helm install loki grafana/loki-distributed \
  --namespace monitoring \
  -f loki-values.yaml
```

```yaml
# loki-values.yaml (production)
loki:
  storage:
    type: s3
    s3:
      bucketnames: company-logs
      region: eu-west-1
      
  schemaConfig:
    configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

  limits_config:
    retention_period: 744h    # 31 gün
    max_query_series_limit: 5000
    max_entries_limit_per_query: 10000
    ingestion_rate_mb: 16
    ingestion_burst_size_mb: 32
```

---

## Promtail — Log Toplayıcı

```yaml
# promtail-config.yaml
scrape_configs:
- job_name: kubernetes-pods
  kubernetes_sd_configs:
  - role: pod

  pipeline_stages:
  # JSON log satırlarını parse et
  - json:
      expressions:
        level: level
        msg: message
        ts: timestamp
        request_id: request_id

  # Label olarak ekle
  - labels:
      level:
      request_id:

  # Belirli log'ları filtrele (debug'ı atla)
  - drop:
      expression: '.*level="debug".*'
      drop_counter_reason: debug_logs

  # Multiline (stack trace'leri birleştir)
  - multiline:
      firstline: '^\d{4}-\d{2}-\d{2}'
      max_wait_time: 3s

  relabel_configs:
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  - source_labels: [__meta_kubernetes_container_name]
    target_label: container
  - source_labels: [__meta_kubernetes_pod_label_app]
    target_label: app
```

---

## LogQL — Sorgu Dili

### Log Stream Seçici

```logql
# Temel: namespace + app label
{namespace="production", app="api"}

# Regex ile
{namespace=~"production|staging"}

# Belirli container
{namespace="production", container="api", pod=~"api-.*"}
```

### Log Filtresi

```logql
# Metin içerme
{app="api"} |= "ERROR"

# Metin dışlama
{app="api"} != "healthcheck"

# Regex eşleşme
{app="api"} |~ "error|exception|fatal"
{app="api"} !~ "GET /healthz"

# JSON parse + field filtreleme
{app="api"} | json | level="error" | status_code >= 500

# Logfmt parse
{app="worker"} | logfmt | duration > 500ms
```

### Metrik Sorguları

```logql
# Son 5 dakikada ERROR sayısı (rate)
rate({namespace="production"} |= "ERROR" [5m])

# App bazında hata oranı
sum by (app) (
  rate({namespace="production"} | json | level="error" [5m])
)

# P99 request süresi (JSON log'dan)
quantile_over_time(0.99,
  {app="api"} | json | unwrap duration_ms [5m]
) by (endpoint)

# Her 5 dakikada toplam istek sayısı
sum(count_over_time({app="api"}[5m]))
```

---

## Label Stratejisi (Kritik!)

Loki'de en yaygın hata: çok fazla label = **yüksek kardinalite** = yavaş sorgular ve yüksek bellek.

```
# ❌ YANLIŞ — Yüksek kardinalite label'lar
{user_id="12345"}          # Milyonlarca farklı değer
{request_id="abc-123"}     # Her istek farklı
{ip_address="1.2.3.4"}     # Çok fazla unique değer

# ✅ DOĞRU — Düşük kardinalite label'lar
{namespace="production"}   # Az sayıda değer
{app="api"}                # Az sayıda servis
{level="error"}            # Birkaç değer (debug/info/warn/error)
{env="prod"}               # Birkaç ortam

# Yüksek kardinalite veriler → Log satırı içinde tut, label yapma
{app="api"} | json | user_id="12345"  # Sorguda filtrele, label değil
```

---

## Grafana ile Log Görselleştirme

```json
// Grafana Panel — Log görünümü
{
  "type": "logs",
  "targets": [{
    "expr": "{namespace=\"production\", app=\"api\"} |= \"ERROR\"",
    "datasource": "Loki"
  }],
  "options": {
    "showTime": true,
    "sortOrder": "Descending",
    "wrapLogMessage": true,
    "enableLogDetails": true
  }
}
```

### Loki + Prometheus Korelasyonu

```json
// Grafana Panel — Metrik altında ilgili log'lar
// datasource: Loki
// Prometheus yüksek hata oranı gösterince → Loki'de aynı zaman diliminde ERROR

{
  "type": "timeseries",
  "links": [{
    "title": "Log'lara git",
    "url": "/explore?left={\"datasource\":\"Loki\",\"queries\":[{\"expr\":\"{app=\\\"api\\\"} |= \\\"ERROR\\\"\"}]}"
  }]
}
```

---

## Alerting (LogQL Alert Rules)

```yaml
# Grafana Alert Rule — LogQL ile
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: loki-alerts
  namespace: monitoring
spec:
  groups:
  - name: loki.rules
    rules:
    # Son 5 dakikada 100'den fazla ERROR
    - alert: HighErrorRate
      expr: |
        sum(rate({namespace="production"} |= "ERROR" [5m])) > 100
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Yüksek hata oranı: production namespace"

    # OOMKill tespiti
    - alert: OOMKillDetected
      expr: |
        sum(count_over_time({namespace="production"} |= "OOMKilled" [5m])) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Pod OOMKilled: {{ $labels.pod }}"
```

---

## Log Retention & Lifecycle

```yaml
# Namespace bazında farklı retention
limits_config:
  per_tenant_override_config: /etc/loki/overrides.yaml

# overrides.yaml
overrides:
  production:
    retention_period: 744h    # 31 gün
  staging:
    retention_period: 168h    # 7 gün
  development:
    retention_period: 72h     # 3 gün
```

---

## Yönetim ve Sorun Giderme

```bash
# Loki'nin hazır olup olmadığı
kubectl get pods -n monitoring -l app=loki

# Loki API durumu
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/ready

# İngestion hızı kontrolü
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/metrics | \
  grep loki_distributor_bytes_received

# Log'ların Loki'ye ulaştığını doğrula
kubectl exec -n monitoring loki-0 -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/labels' | jq .

# Promtail log'ları
kubectl logs -n monitoring -l app=promtail --tail=20
```

> [!TIP]
> Loki'de sorgu yavaşsa ilk kontrol: label kardinalitesi. `{namespace="production"}` ile başlayıp daraltın. `|=` filtresi Loki'nin güçlü yanı — index gerekmez, log satırları üzerinde çalışır.
