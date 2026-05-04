# Distributed Tracing — Tempo & OpenTelemetry

Metrik "ne kadar?" sorusunu, log "ne oldu?" sorusunu yanıtlar. **Dağıtık izleme (distributed tracing)** ise "nerede gecikti?" sorusunu — tek bir isteğin onlarca mikroservis üzerinden geçtiği yolculuğu — görünür kılar.

---

## Temel Kavramlar

```
İstek → Service A → Service B → Service C → DB
         100ms      250ms       50ms        800ms
         
Toplam: 1200ms — Ama hangi servis sorunlu?

Trace ID: abc-123 (tek isteğin kimliği)
  └── Span: A (100ms)
       └── Span: B (250ms)
            └── Span: C (50ms)
                 └── Span: DB query (800ms) ← Sorun burada!
```

**Terimler:**
- **Trace**: Bir isteğin uçtan uca yolculuğu
- **Span**: Tek bir operasyonun süresi ve metadata'sı
- **Context Propagation**: Trace ID'nin servisler arası aktarımı

---

## OpenTelemetry (OTel)

2026'da tracing için standart: OpenTelemetry. Vendor-agnostic, hem SDK hem Collector içerir.

```bash
# OpenTelemetry Operator kurulumu
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
```

### OTel Collector (DaemonSet modu)

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  mode: DaemonSet    # Her node'da bir collector

  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      # Mevcut Jaeger istemcilerini de kabul et
      jaeger:
        protocols:
          thrift_http:
            endpoint: 0.0.0.0:14268

    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
      memory_limiter:
        limit_mib: 512
        spike_limit_mib: 128
      # Hassas bilgileri temizle
      attributes:
        actions:
        - key: db.statement
          action: delete     # SQL sorgusunu loglamayın
        - key: http.request.header.authorization
          action: delete

    exporters:
      otlp:
        endpoint: tempo.monitoring:4317
        tls:
          insecure: true
      # Prometheus'a metrik gönder
      prometheus:
        endpoint: "0.0.0.0:8889"

    service:
      pipelines:
        traces:
          receivers: [otlp, jaeger]
          processors: [memory_limiter, batch]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheus]
```

### Auto-Instrumentation (Kod değişikliği olmadan)

```yaml
# OTel Operator ile Java/Node/Python uygulamalarını otomatik instrument et
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: auto-instrumentation
  namespace: production
spec:
  exporter:
    endpoint: http://otel-collector.monitoring:4318

  # Java
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
    env:
    - name: OTEL_TRACES_SAMPLER
      value: "parentbased_traceidratio"
    - name: OTEL_TRACES_SAMPLER_ARG
      value: "0.1"    # %10 örnekleme

  # Python
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:latest

  # Node.js
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:latest
```

```yaml
# Pod'a annotation ekle — sidecar otomatik enjekte edilir
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"
    # veya: inject-python, inject-nodejs
```

---

## Grafana Tempo — Trace Backend

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm install tempo grafana/tempo-distributed \
  --namespace monitoring \
  --set storage.trace.backend=s3 \
  --set storage.trace.s3.bucket=company-traces \
  --set storage.trace.s3.region=eu-west-1 \
  --set ingester.replicas=3 \
  --set querier.replicas=2 \
  --set compactor.replicas=1
```

### Tempo Yapılandırması

```yaml
# values.yaml
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: company-traces
        endpoint: s3.eu-west-1.amazonaws.com
        region: eu-west-1

  # Retention
  compactor:
    compaction:
      block_retention: 336h   # 14 gün

  # TraceQL — Tempo'nun sorgu dili
  query_frontend:
    search:
      default_result_limit: 20
      max_result_limit: 100
```

---

## Manuel Instrumentation

```python
# Python — OpenTelemetry SDK
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
import os

# Tracer kur
provider = TracerProvider()
exporter = OTLPSpanExporter(
    endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Span oluştur
def process_order(order_id: str):
    with tracer.start_as_current_span("process_order") as span:
        span.set_attribute("order.id", order_id)
        span.set_attribute("service.version", "2.1.0")

        # Alt span
        with tracer.start_as_current_span("validate_inventory"):
            result = check_inventory(order_id)
            span.set_attribute("inventory.available", result)

        with tracer.start_as_current_span("charge_payment") as payment_span:
            try:
                charge(order_id)
            except Exception as e:
                payment_span.record_exception(e)
                payment_span.set_status(trace.StatusCode.ERROR)
                raise
```

```go
// Go — OpenTelemetry SDK
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
)

tracer := otel.Tracer("order-service")

func ProcessOrder(ctx context.Context, orderID string) error {
    ctx, span := tracer.Start(ctx, "ProcessOrder")
    defer span.End()

    span.SetAttributes(
        attribute.String("order.id", orderID),
        attribute.String("service.version", "2.1.0"),
    )

    if err := validateInventory(ctx, orderID); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return err
    }
    return nil
}
```

---

## Grafana'da TraceQL

```
# Tempo'yu Grafana'ya ekle: Explore → Tempo datasource

# Belirli servisin tüm trace'leri
{ resource.service.name = "orders-service" }

# 500ms üzeri süren trace'ler
{ duration > 500ms }

# Hatalı span'lar
{ status = error }

# Belirli endpoint'e gelen yavaş istekler
{ resource.service.name = "api" && http.url =~ "/orders.*" && duration > 1s }

# Trace ID ile doğrudan ara
{ traceID = "abc123def456" }
```

---

## Metrics + Logs + Traces Korelasyonu (Grafana)

```
Grafana Explore:
  1. Prometheus'ta yüksek latency görürsün
  2. Aynı zaman aralığında Loki'de error loglar
  3. "View in Tempo" ile trace'e git
  4. Hangi span yavaş olduğunu tespit et

Bu üçlüye "LGTM Stack" denir:
  Loki + Grafana + Tempo + Mimir (uzun vadeli Prometheus)
```

> [!TIP]
> %100 trace örnekleme production'da disk ve CPU maliyetini katlar. `parentbased_traceidratio: 0.1` ile %10 örnekleme genellikle yeterlidir. Hatalı istekleri her zaman örneklemek için **head-based + tail-based** sampling kombinasyonu kullanın.
