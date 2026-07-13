# Tempo ve OpenTelemetry ile Dağıtık İzleme (Distributed Tracing)

Merkezi metrikler (Prometheus) "sistem ne kadar yüklü?" veya "hata oranı nedir?" sorularını yanıtlar. Merkezi loglar (Loki) ise "hata anında ne oldu?" sorusuna yanıt verir. Ancak tek bir kullanıcı isteğinin onlarca farklı mikroservis (Gateway, Auth, Billing, Shipping vb.) arasından geçtiği karmaşık sistemlerde, "istek nerede gecikti?" sorusunun yanıtı sadece **Dağıtık İzleme (Distributed Tracing)** ile verilebilir.

---

## 1. Dağıtık İzleme Temel Kavramları

Bir isteğin (request) tüm servisler arasındaki yolculuğunu gözlemlemek için şu kavramlar kullanılır:

```
[Kullanıcı İsteği] ──► [ API Gateway ] (Span 1: 100ms)
                           │
                           ▼
                      [ Auth Servis ] (Span 2: 50ms)
                           │
                           ▼
                      [ Sipariş Servisi ] (Span 3: 1050ms)
                           │
                           ▼
                      [ Veritabanı Sorgusu ] (Span 4: 900ms)  <=== Gecikme Kaynağı!
```

* **Trace (İz):** Bir isteğin uçtan uca yaptığı tüm yolculuğu ve bu yolculuğun benzersiz kimliğini (**Trace ID**) temsil eder.
* **Span (Aralık):** Bu yolculuk içindeki tek bir iş birimini (Örn: HTTP çağrısı, veritabanı sorgusu, şifreleme işlemi) ve süresini temsil eder. Her span'ın kendine ait bir **Span ID**'si ve üst span referansı (**Parent ID**) bulunur.
* **Context Propagation (Bağlam Aktarımı):** Trace ID ve Span ID bilgilerinin HTTP başlıkları (headers) veya gRPC metadata'ları aracılığıyla bir servisten diğerine taşınması işlemidir (Örn: `traceparent` header standardı).

---

## 2. OpenTelemetry (OTel) ile Entegrasyon

İzleme verilerini toplamak için OpenTelemetry Operator ve OTel Collector kullanılır.

* **OTel Collector (DaemonSet):** Her node üzerinde çalışarak podların 4317 (gRPC) veya 4318 (HTTP) portlarına gönderdiği OTLP trace verilerini toplar.
* **Auto-Instrumentation:** Uygulama koduna hiç dokunmadan, Kubernetes deployment dosyalarına eklenen etiketler (annotations) aracılığıyla otomatik izleme ajanı enjekte edilir.

*(Detaylar ve otomatik enjeksiyon şablonları için bkz: [opentelemetry.md](opentelemetry.md))*

---

## 3. Grafana Tempo Nedir ve Nasıl Kurulur?

**Grafana Tempo**, yüksek ölçeklenebilirliğe sahip, sadece nesne depolama (S3, GCS vb.) kullanan ve arama işlemlerini Trace ID üzerinden çok hızlı gerçekleştiren yeni nesil bir trace veritabanıdır.

### Tempo Distributed (S3 Arkasında) Kurulum Değerleri (`tempo-values.yaml`)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [dagitik_izleme_tempo_manifest_1.yaml](../Manifests/08_observability/dagitik_izleme_tempo_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Kurulum komutu:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install tempo grafana/tempo-distributed \
  --namespace monitoring \
  -f tempo-values.yaml
```

---

## 4. Kod Düzeyinde Manuel İzleme (SDK)

Otomatik izlemenin yetersiz kaldığı durumlarda veya iş akışınızdaki kritik adımları detaylandırmak için kod içinde manuel span'lar oluşturabilirsiniz:

### Python Örneği (OpenTelemetry SDK)

```python
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# 1. SDK ve Exporter Yapılandırması
provider = TracerProvider()
exporter = OTLPSpanExporter(
    endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# 2. Kod içinde Span Oluşturma
def process_order(order_id: str):
    with tracer.start_as_current_span("process_order_main") as span:
        span.set_attribute("order.id", order_id)
        span.set_attribute("app.version", "1.4.0")

        # Alt (Child) Span Oluşturma
        with tracer.start_as_current_span("validate_db_stock") as child_span:
            try:
                # Veritabanı sorgulama simülasyonu
                stock_ok = True
                child_span.set_attribute("stock.status", stock_ok)
            except Exception as e:
                child_span.record_exception(e)
                child_span.set_status(trace.StatusCode.ERROR, str(e))
                raise
```

---

## 5. Grafana üzerinde TraceQL ile Sorgulama

Tempo veri kaynağı Grafana'ya eklendikten sonra, **TraceQL** sorgu dili kullanılarak yavaş veya hatalı izler saniyeler içinde filtrelenebilir:

```traceql
# 1. Sadece "billing-service" uygulamasına ait izleri getirin:
{ resource.service.name = "billing-service" }

# 2. Çalışma süresi 1 saniyeden uzun süren yavaş istekleri bulun:
{ duration > 1s }

# 3. Hata (Error) almış olan tüm span'ları listeleyin:
{ status = error }

# 4. API uygulamasında "/checkout" adresine gelen ve 800ms'den uzun süren hatalı istekleri süzün:
{ resource.service.name = "api-gateway" && http.target =~ "/checkout.*" && duration > 800ms }
```

---

## 6. Gözlemlenebilirlik Altın Döngüsü (Korelasyon)

Gerçek bir sistem kesintisinde (Incident) sorun giderme süresi (**MTTR**) şu adımlarla en aza indirilir:

```
[ Grafana CPU Grafiği ] ──► (Sıradışı Tepe Noktası)
        │
        ▼ (Tek Tıkla Geçiş)
[ Loki Hata Logları ]    ──► (Log satırındaki derived fields Trace ID linki)
        │
        ▼ (Tek Tıkla Geçiş)
[ Tempo TraceQL Ekranı ] ──► (Yavaş çalışan SQL veya hata alan dış servis tespiti)
```

---

## 7. Örnekleme (Sampling) Stratejileri ile Maliyet Yönetimi

Üretim ortamlarında saniyede on binlerce istek alan sistemlerin tüm izleme verilerini ( %100 Traces) depolamak devasa disk maliyetlerine ve CPU yüküne sebep olur.

* **Head-based Sampling (Girişte Örnekleme):** İstek henüz başlarken belirlenen bir orana göre (Örn: `%10` oranında `trace.TraceIDRatioBased(0.1)`) trace edilip edilmeyeceğine karar verilir. Basittir ancak hata alan veya yavaş çalışan önemli isteklerin kaçırılmasına yol açabilir.
* **Tail-based Sampling (Çıkışta Örnekleme):** OTel Collector, tüm isteklerin traces verilerini geçici olarak bellekte toplar. İstek tamamlandığında, eğer istek hata almışsa (HTTP 5xx) veya gecikmesi yüksekse (Örn: > 1s) bu trace verisini **kesinlikle saklar**, başarılı ve hızlı olanların ise çoğunu eler. Bu yöntem depolama maliyetini %90 düşürürken kritik hataları kaçırmaz.
