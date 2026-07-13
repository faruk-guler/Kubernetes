# Knative Eventing ile Olay Güdümlü (Event-Driven) Mimari

HTTP tabanlı istekleri ve sıfıra ölçeklemeyi (Scale-to-Zero) yöneten Knative Serving bileşeninin yanı sıra, asenkron ve gevşek bağlı (**loosely coupled**) olay güdümlü mimariler kurmak için **Knative Eventing** kullanılır. Knative Eventing; mesaj kuyruklarını, event akışlarını ve asenkron mikroservis haberleşmesini Kubernetes-native nesneler (CRD'ler) aracılığıyla standartlaştırır.

---

## 1. Temel Bileşenler ve Kavramlar

Knative Eventing mimarisinde mesajlar **CloudEvents v1.0** standart protokolüyle HTTP POST istekleri olarak taşınır.

```
┌──────────────┐           ┌──────────────┐           ┌──────────────┐           ┌──────────────┐
│ Event Source │ ──(Push)─►│    Broker    │ ──(Filter)►│   Trigger    │ ──(Send)─►│  Sink (App)  │
└──────────────┘           └──────────────┘           └──────────────┘           └──────────────┘
```

* **Source (Olay Kaynağı):** Olayı üreten ve CloudEvent formatına dönüştüren bileşen (Örn: Kafka, GitHub Webhook, Kubernetes API).
* **Broker (Olay Dağıtıcı):** Olayları kabul eden ve uygun tüketicilere dağıtan merkezi santral.
* **Trigger (Tetikleyici):** Belirli etiket veya filtrelere uyan olayları Broker'dan çekerek hedef servise (Sink) yönlendiren kural.
* **Channel (Kanal):** Mesajların güvenli taşındığı tampon bellek hattı (Örn: InMemory, Kafka, RabbitMQ).
* **Sink (Hedef):** Olayı alan ve işleyen son nokta (Kubernetes Service, Knative Service veya bir URL).

---

## 2. Kurulum ve Altyapı Hazırlığı

Knative Eventing çekirdeğini ve mesaj depolama kanallarını kurmak için:

```bash
# 1. Knative Eventing Çekirdeğini Kurun
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/eventing-crds.yaml
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/eventing-core.yaml

# 2. InMemoryChannel (Geliştirme / Test için bellek içi kanal) Kurulumu
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/in-memory-channel.yaml

# 3. Çoklu Kanallı (MT-Channel-Based) Broker Kurulumu
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/mt-channel-broker.yaml

# 4. Üretim Ortamları İçin Kafka Broker Eklentisi (Opsiyonel)
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/latest/download/eventing-kafka-controller.yaml
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/latest/download/eventing-kafka-broker.yaml
```

---

## 3. Broker ve Trigger (Merkezi Dağıtım Kalıbı)

Mesaj üreticisi (source) doğrudan hangi servisi çağıracağını bilmez; olayı sadece `Broker`'a yollar. `Trigger` ise bu olayları filtreleyip hedefe yönlendirir.

### A. Broker Tanımı (`broker.yaml`)

```yaml
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: default-event-broker
  namespace: production
```

### B. Trigger Tanımı (`trigger.yaml`)

Sadece `type: order.created` olan olayları yakalayıp `billing-service` isimli pod'a gönderen tetikleyici:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [knative_eventing_manifest_1.yaml](../Manifests/09_gitops/knative_eventing_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. ApiServerSource ile Kubernetes Olaylarını Dinleme

Kubernetes kümesinde gerçekleşen sistem olaylarını (örneğin yeni bir pod oluşturulması) dinleyip bunları CloudEvent formatında Broker'a yönlendirmek için **ApiServerSource** kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [knative_eventing_manifest_2.yaml](../Manifests/09_gitops/knative_eventing_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. KafkaSource ile Kafka Olaylarını Tüketme

Harici bir Apache Kafka kümesindeki bir konudan (topic) gelen mesajları okuyup Kubernetes üzerinde çalışan Serverless servislere iletmek için **KafkaSource** kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [knative_eventing_manifest_3.yaml](../Manifests/09_gitops/knative_eventing_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. CloudEvents Standardı ve Kodlama (Go SDK)

Knative Eventing mesajları standart HTTP POST istekleriyle taşır. HTTP başlıkları (headers) metadata bilgilerini tutar:

```http
POST / HTTP/1.1
Host: default-broker.production.svc.cluster.local
Content-Type: application/json
ce-specversion: 1.0
ce-type: order.created
ce-source: /store/billing-system
ce-id: abc-12345-xyz
ce-time: 2026-07-11T12:00:00Z

{
  "orderId": "ORD-9988",
  "amount": 250.50
}
```

### Go ile CloudEvent Mesajı Üretme

```go
package main

import (
 "context"
 cloudevents "github.com/cloudevents/sdk-go/v2"
)

func main() {
 ctx := context.Background()
 // 1. CloudEvents istemcisi oluşturun
 client, _ := cloudevents.NewClientHTTP()

 // 2. Mesaj nesnesini hazırlayın
 event := cloudevents.NewEvent()
 event.SetID("abc-12345-xyz")
 event.SetSource("/store/billing-system")
 event.SetType("order.created")
 event.SetData(cloudevents.ApplicationJSON, map[string]interface{}{
  "orderId": "ORD-9988",
  "amount":  250.50,
 })

 // 3. Mesajı Broker adresine gönderin
 ctx = cloudevents.ContextWithTarget(ctx, "http://default-broker.production.svc.cluster.local")
 client.Send(ctx, event)
}
```

---

## 7. Delivery Hata Yönetimi ve Dead Letter Queue (DLQ)

Eğer hedef servis (Sink) çöktüyse veya hata veriyorsa (HTTP 5xx), mesajın kaybolmaması için **Yeniden Deneme (Retry)** ve **Dead Letter Queue (Çöp Kutusu / DLQ)** politikaları tanımlanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [knative_eventing_manifest_4.yaml](../Manifests/09_gitops/knative_eventing_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 8. Hata Ayıklama ve Olay İzleme (Debugging)

```bash
# 1. Broker durumunu sorgulayın
kubectl get brokers -n production

# 2. Tetikleyicilerin sağlıklı çalışıp çalışmadığını kontrol edin
kubectl get triggers -n production

# 3. Gelen CloudEvents mesajlarını ekrana yazdıran geçici bir dinleyici (display app) çalıştırın:
kubectl run event-display --image=gcr.io/knative-releases/knative.dev/eventing/cmd/event_display -n production

# 4. Bu dinleyicinin loglarından gelen ham JSON ve HTTP başlıklarını anlık okuyun:
kubectl logs event-display -n production -f
```
