# OpenTelemetry ile Standartlaşmış Gözlemlenebilirlik (OpenTelemetry Guide)

Gözlemlenebilirlik (observability) dünyası geçmişte her izleme aracının (Datadog, Dynatrace, Prometheus, Jaeger) kendine özel kütüphaneler (SDK) ve protokoller kullanmasından dolayı ciddi bir araç bağımlılığı kilitlemesine (**vendor lock-in**) yol açıyordu. 2026 yılı kurumsal izleme standartlarında bu sorunun mutlak çözümü CNCF projesi olan **OpenTelemetry (OTel)** standardıdır.

OpenTelemetry; metriklerin, logların ve dağıtık izleme (traces) verilerinin tek bir formatta (**OTLP - OpenTelemetry Protocol**) üretilmesini, işlenmesini ve istenen herhangi bir arka plana (Tempo, Loki, Datadog, Prometheus vb.) sadece bir konfigürasyon değişikliğiyle gönderilmesini sağlar.

---

## 1. OpenTelemetry Operator Kurulumu

Kubernetes üzerinde OpenTelemetry altyapısını ve otomatik kod enjeksiyonunu (Auto-Instrumentation) yönetmek için **OTel Operator** kullanılır:

```bash
# 1. OpenTelemetry Helm deposunu ekleyin
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# 2. Operatörü kurun (Arka planda cert-manager kurulu olmalıdır)
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry \
  --create-namespace \
  --set admissionWebhooks.certManager.enabled=true \
  --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib
```

---

## 2. OTel Collector Mimarisi ve Pipeline Yapısı

OTel Collector, verileri toplayan, işleyen ve dışa aktaran bağımsız bir proxy sunucusudur. Pipeline akış yapısı şu şekildedir:

```
[ Uygulama Pod'u ] ──► ( OTLP/gRPC ) ──► [ Receiver ] ──► [ Processor ] ──► [ Exporter ] ──► [ Tempo/Mimir ]
```

* **Receivers (Alıcılar):** Verilerin hangi formatta ve portta kabul edileceğini belirler (OTLP, Zipkin, Jaeger, Prometheus).
* **Processors (İşlemciler):** Gelen verileri filtreler, gruplar, kişisel verileri maskeler (PII) veya yığınlar halinde birleştirir (batch).
* **Exporters (İhracatçılar):** İşlenen verileri hangi izleme arkadizimine (backend) göndereceğini belirler (OTLP/gRPC, Loki, Tempo, Kafka vb.).

---

## 3. OTel Collector Yapılandırmaları (DaemonSet vs. Gateway)

### A. DaemonSet Collector (Node Ajanı Modeli)

Her worker node üzerinde DaemonSet olarak çalışır, yerel podlardan gelen verileri en düşük gecikmeyle (low-latency) toplar.

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [opentelemetry_manifest_1.yaml](../Manifests/08_observability/opentelemetry_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Gateway Collector (Merkezi Veri Yönlendirici)

DaemonSet ajanlarından gelen tüm verileri toplayıp, dışarıdaki depolama katmanlarına (Tempo, Loki, Prometheus) veya bulut servislerine gönderen merkezi yük dengeleyici.

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [opentelemetry_manifest_2.yaml](../Manifests/08_observability/opentelemetry_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Auto-Instrumentation (Sıfır Kod Değişikliğiyle İzleme)

OpenTelemetry Operator'ın en güçlü özelliklerinden biri, podlar oluşturulurken kodun içine hiç dokunmadan otomatik olarak OTel Java/Node.js/Python/Go ajanlarını enjekte edebilmesidir.

### 1. `Instrumentation` Kaynağını Oluşturun

Bu kaynak, ajanların nereye bağlanacağını (Collector adresi) ve hangi dillerin desteklendiğini tanımlar:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [opentelemetry_manifest_3.yaml](../Manifests/08_observability/opentelemetry_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### 2. Uygulama Deployment Tanımına Annotation Ekleme

Uygulama deployment dosyanıza tek satır açıklama ekleyerek otomatik izlemeyi aktif edebilirsiniz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [opentelemetry_manifest_4.yaml](../Manifests/08_observability/opentelemetry_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Artık uygulamanın yaptığı tüm HTTP istekleri, veritabanı sorguları ve dış API bağlantıları otomatik olarak izlenecek ve Tempo üzerinden görselleştirilecektir. Geliştiricinin tek satır izleme kodu yazmasına gerek kalmaz.

---

## 5. Go dili ile Manuel SDK İzleme (Custom Spans)

Otomatik izlemenin yetmediği, iş mantığınıza özel adımların (Örn: sipariş onaylama adımı) izlenmesi istendiğinde SDK kullanılarak kod düzeyinde izleme yapılır:

```go
package main

import (
 "context"
 "go.opentelemetry.io/otel"
 "go.opentelemetry.io/otel/attribute"
 "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
 "go.opentelemetry.io/otel/sdk/trace"
)

func initTracer() {
 ctx := context.Background()
 // Collector adresine bağlantı kur
 exporter, _ := otlptracegrpc.New(ctx,
  otlptracegrpc.WithEndpoint("otel-collector.opentelemetry.svc.cluster.local:4317"),
  otlptracegrpc.WithInsecure(),
 )

 // Tracer sağlayıcısını tanımla (%10 sampling - örnekleme oranıyla)
 tp := trace.NewTracerProvider(
  trace.WithBatcher(exporter),
  trace.WithSampler(trace.TraceIDRatioBased(0.1)),
 )
 otel.SetTracerProvider(tp)
}

func ProcessOrder(ctx context.Context, orderID string, amount int) {
 // Yeni bir izleme adımı (Span) başlat
 tracer := otel.Tracer("order-service")
 ctx, span := tracer.Start(ctx, "process-order-step")
 defer span.End() // İşlem bitiminde span'ı kapat ve gönder

 // Span içine özel etiketler ekle
 span.SetAttributes(
  attribute.String("order.id", orderID),
  attribute.Int("order.amount", amount),
 )
}
```

---

## 6. Collector Sağlık Durumu ve Metrik Denetimleri

```bash
# 1. Kümedeki aktif OTel Collector listesini görüntüleme
kubectl get opentelemetrycollectors -n opentelemetry

# 2. Collector iç metrik sunucusuna port-forward yapma
kubectl port-forward -n opentelemetry svc/otel-gateway-collector 8888:8888

# 3. İletilen ve düşürülen (drop) paket metriklerini kontrol edin:
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted_spans_total
```
