# LGTM Stack — Kapsamlı Gözlemlenebilirlik

"Çalışıyor gibi görünüyor" demek 2026'da yeterli değildir. Sistemin iç yapısını, performansını ve hatalarını anlık olarak görebilmemiz gerekir.

## LGTM Stack Nedir?

| Harf | Araç | Görev |
|:----:|:-----|:------|
| **L** | **Loki** | Log toplama ve sorgulama (indekssiz, etiket bazlı) |
| **G** | **Grafana** | Metrik, log ve trace görselleştirme — tek dashboard |
| **T** | **Tempo** | Dağıtık izleme (distributed tracing) |
| **M** | **Mimir** | Uzun süreli metrik depolama (Prometheus uyumlu) |

---

### Geleneksel İzleme: EFK Stack (1w2.net Referans)
Modern LGTM yapısına geçmeden önce sektörde standart olan **EFK Stack** bileşenlerini bilmek operasyonel olarak önemlidir:
- **Elasticsearch:** Logların indekslendiği ve saklandığı veritabanı.
- **Fluentd (veya Logstash):** Node'lardan logları toplayıp Elasticsearch'e gönderen ajan.
- **Kibana:** Logları görselleştirme arayüzü.

> [!WARNING]
> **Neden LGTM?** EFK stack, özellikle Elasticsearch'ün yüksek kaynak tüketimi (RAM/CPU) nedeniyle yönetimi zorlaşmıştır. **Grafana Loki**, logları indekslemek yerine etiketlediği için %90 daha az depolama alanı ve CPU kullanır. 2026 standartlarında bu nedenle LGTM tercih edilir.

## kube-prometheus-stack Kurulumu

Prometheus + Grafana + Alertmanager hepsi bir arada:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="SecureGrafanaPass2026!" \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi
```

> [!TIP]
> 2026 standardı: kube-prometheus-stack ArgoCD üzerinden GitOps ile yönetilmeli. Bu komutları ArgoCD Application YAML'ına taşıyın.

## Loki ile Log Yönetimi

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set grafana.enabled=false    # Zaten prometheus-stack ile var
```

**LogQL örneği (Grafana Explore):**

```logql
# Production'daki hata logları
{namespace="production", app="web-app"} |= "ERROR" | json | line_format "{{.message}}"

# Son 5 dakikada 500 hata sayısı
sum(rate({namespace="production"} |= "500" [5m])) by (app)
```

## Alertmanager ile Uyarılar

```yaml
# PrometheusRule örneği
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts
  namespace: monitoring
  labels:
    release: prometheus    # kube-prometheus-stack selector
spec:
  groups:
  - name: application
    rules:
    - alert: HighErrorRate
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[5m])) /
        sum(rate(http_requests_total[5m])) > 0.05
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Yüksek hata oranı tespit edildi"
        description: "{{ $labels.app }} uygulamasında %5'ten fazla 5xx hatası"

    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod sürekli crash oluyor: {{ $labels.pod }}"
```

## Grafana Dashboard'ları

```bash
# Grafana UI erişimi
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Hazır dashboard ID'leri (grafana.com/dashboards):
# 15757 → Kubernetes Cluster Overview
# 13659 → Loki Log Dashboard
# 16611 → Cilium/Hubble Dashboard
# 15172 → Node Exporter Full
```

## Altın Sinyaller (The Four Golden Signals)

Her uygulamada mutlaka takip edilmesi gereken 4 metrik:

| Sinyal | Açıklama | Örnek PromQL |
|:---|:---|:---|
| **Latency** | İstek yanıt süresi | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` |
| **Traffic** | Saniyedeki istek sayısı | `sum(rate(http_requests_total[5m]))` |
| **Errors** | Hata oranı | `sum(rate(http_requests_total{code=~"5.."}[5m]))` |
| **Saturation** | Kaynak doluluk oranı | `container_memory_usage_bytes / container_spec_memory_limit_bytes` |
