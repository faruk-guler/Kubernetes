# OpenTelemetry — Standartlaşmış Gözlemlenebilirlik

## 3.1 OpenTelemetry Nedir?

2026'da her uygulama kendi metriklerini, loglarını ve tracelerini **OpenTelemetry (OTel)** formatında yayınlar. Bu sayede backend değişim maliyeti ortadan kalkar: Jaeger'dan Tempo'ya, Datadog'dan Grafana Cloud'a geçmek sadece birkaç satır YAML değişikliği.

## 3.2 Üç Temel Sinyal

| Sinyal | Görev | Araç |
|:---|:---|:---|
| **Metrics** | Sayısal ölçümler (CPU, RPS, hata sayısı) | Prometheus / Mimir |
| **Logs** | Olay kayıtları | Loki |
| **Traces** | İstek yolculuğu (hangi servis nerede yavaşladı?) | Tempo / Jaeger |

## 3.3 OTel Operator Kurulumu

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry \
  --create-namespace \
  --set admissionWebhooks.certManager.enabled=true
```

## 3.4 OTel Collector Yapılandırması

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: cluster-collector
  namespace: opentelemetry
spec:
  mode: DaemonSet       # Her node'da çalışır
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      prometheus:
        config:
          scrape_configs:
          - job_name: 'kubernetes-pods'
            kubernetes_sd_configs:
            - role: pod

    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
      memory_limiter:
        limit_mib: 400
        spike_limit_mib: 100

    exporters:
      otlp/tempo:
        endpoint: http://tempo.monitoring:4317
        tls:
          insecure: true
      loki:
        endpoint: http://loki.monitoring:3100/loki/api/v1/push
      prometheusremotewrite:
        endpoint: http://prometheus.monitoring:9090/api/v1/write

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp, prometheus]
          processors: [memory_limiter, batch]
          exporters: [prometheusremotewrite]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [loki]
```

## 3.5 Auto-Instrumentation (Otomatik Enstrümantasyon)

OTel Operator, uygulamaya kod eklemeden otomatik instrumentation yapabilir:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: auto-instrumentation
  namespace: production
spec:
  exporter:
    endpoint: http://cluster-collector.opentelemetry:4317
  propagators:
  - tracecontext
  - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"   # %10 sampling
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.32.0
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.46.0
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.44b0
```

Uygulamayı işaretlemek için sadece annotation yeterli:

```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"
    # veya inject-nodejs, inject-python, inject-go
```

> [!TIP]
> Auto-instrumentation ile uygulama koduna dokunmadan tüm HTTP isteklerini, veritabanı sorgularını ve servisler arası çağrıları Tempo üzerinden izleyebilirsiniz. Bu özellikle eski (legacy) uygulamalarda çok değerlidir.

