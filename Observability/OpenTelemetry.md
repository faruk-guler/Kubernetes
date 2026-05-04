# OpenTelemetry — Standartlaşmış Gözlemlenebilirlik

2026'da her uygulama metrik, log ve trace'ini **OpenTelemetry (OTel)** formatında yayınlar. Backend değişikliği artık YAML değişikliği — Jaeger'dan Tempo'ya, Datadog'dan Grafana Cloud'a geçiş birkaç satır.

---

## Üç Temel Sinyal

| Sinyal | Görev | 2026 Backend |
|:-------|:------|:-------------|
| **Traces** | İstek yolculuğu — hangi servis nerede yavaşladı? | Grafana Tempo |
| **Metrics** | Sayısal ölçümler — RPS, hata oranı, CPU | Prometheus / Mimir |
| **Logs** | Olay kayıtları — structured JSON | Grafana Loki |

---

## OTel Operator Kurulumu

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry \
  --create-namespace \
  --set admissionWebhooks.certManager.enabled=true \
  --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib

kubectl get pods -n opentelemetry
```

---

## OTel Collector — Pipeline Mimarisi

```
Uygulama → [Receiver] → [Processor] → [Exporter] → Backend
             OTLP               batch              Tempo
             Prometheus         memory_limiter     Mimir
             Kafka              filter             Loki
             Jaeger             transform          Datadog
```

### DaemonSet Collector (Node başına — düşük latency)

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: node-collector
  namespace: opentelemetry
spec:
  mode: DaemonSet
  resources:
    limits:
      cpu: 200m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      hostmetrics:
        collection_interval: 30s
        scrapers:
          cpu: {}
          memory: {}
          disk: {}
          network: {}
      kubeletstats:
        collection_interval: 15s
        auth_type: serviceAccount
        endpoint: "${K8S_NODE_IP}:10250"

    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
      memory_limiter:
        limit_mib: 400
        spike_limit_mib: 80
      resource:
        attributes:
        - action: insert
          key: k8s.cluster.name
          value: production
      resourcedetection:
        detectors: [env, k8s_node, system]
        timeout: 5s
      filter/drop_noisy:
        traces:
          span:
          - 'attributes["http.target"] == "/health"'
          - 'attributes["http.target"] == "/metrics"'

    exporters:
      otlp/tempo:
        endpoint: http://tempo.monitoring:4317
        tls:
          insecure: true
      prometheusremotewrite:
        endpoint: http://prometheus.monitoring:9090/api/v1/write
      loki:
        endpoint: http://loki.monitoring:3100/loki/api/v1/push

    service:
      telemetry:
        logs:
          level: warn
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, filter/drop_noisy, resource, batch]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp, hostmetrics, kubeletstats]
          processors: [memory_limiter, resource, batch]
          exporters: [prometheusremotewrite]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [loki]
```

### Gateway Collector (Merkezi — multi-cluster)

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: gateway-collector
  namespace: opentelemetry
spec:
  mode: Deployment
  replicas: 2
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317

    processors:
      batch: {}
      tail_sampling:           # Sadece ilginç trace'leri sakla (maliyet optimizasyonu)
        decision_wait: 10s
        policies:
        - name: errors-policy
          type: status_code
          status_code: {status_codes: [ERROR]}
        - name: slow-traces-policy
          type: latency
          latency: {threshold_ms: 1000}
        - name: random-sample
          type: probabilistic
          probabilistic: {sampling_percentage: 5}    # %5 random sample

    exporters:
      otlp/tempo:
        endpoint: http://tempo.monitoring:4317
        tls:
          insecure: true

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, tail_sampling]
          exporters: [otlp/tempo]
```

---

## Auto-Instrumentation — Sıfır Kod Değişikliği

OTel Operator, uygulama koduna dokunmadan otomatik instrumentation yapar:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: auto-instrumentation
  namespace: production
spec:
  exporter:
    endpoint: http://node-collector.opentelemetry:4317
  propagators:
  - tracecontext    # W3C TraceContext (standart)
  - baggage
  - b3              # Zipkin uyumluluğu için
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"    # %10 sampling — prod için yeterli
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.x
    env:
    - name: OTEL_INSTRUMENTATION_JDBC_ENABLED
      value: "true"
    - name: OTEL_INSTRUMENTATION_SPRING_WEB_ENABLED
      value: "true"
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.52.x
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.48b0
  go:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-go:0.14.x
```

```yaml
# Deployment'a sadece annotation ekle — başka bir şey gerekmez
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"
    # inject-nodejs, inject-python, inject-go
```

---

## SDK ile Manuel Instrumentation (Go)

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
)

// Tracer başlat
exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("otel-collector:4317"),
    otlptracegrpc.WithInsecure(),
)
tp := trace.NewTracerProvider(
    trace.WithBatcher(exporter),
    trace.WithSampler(trace.TraceIDRatioBased(0.1)),
)
otel.SetTracerProvider(tp)

// Span oluştur
tracer := otel.Tracer("my-service")
ctx, span := tracer.Start(ctx, "process-order")
defer span.End()

span.SetAttributes(
    attribute.String("order.id", orderID),
    attribute.Int("order.amount", amount),
)
```

---

## Collector Health & Metrics

```bash
# Collector durumu
kubectl get opentelemetrycollector -n opentelemetry
kubectl describe opentelemetrycollector node-collector -n opentelemetry

# Collector internal metrikleri
kubectl port-forward -n opentelemetry svc/node-collector-collector 8888:8888
curl http://localhost:8888/metrics | grep otelcol

# Pipeline throughput
# otelcol_receiver_accepted_spans_total
# otelcol_exporter_sent_spans_total
# otelcol_processor_dropped_spans_total
```

> [!TIP]
> Auto-instrumentation ile uygulama koduna dokunmadan tüm HTTP isteklerini, DB sorgularını ve servisler arası çağrıları Tempo üzerinden izleyebilirsiniz. `tail_sampling` ile sadece hatalı veya yavaş trace'leri saklayarak maliyet %95 düşer.
