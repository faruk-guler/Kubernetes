# Knative Eventing — Event-Driven Architecture

Knative Serving HTTP tabanlı serverless için ideal. **Knative Eventing** ise olay güdümlü (event-driven) sistemler için: mesaj kuyrukları, event akışları ve asenkron servisler arası iletişim.

---

## Temel Kavramlar

```
Geleneksel:   Servis A → HTTP POST → Servis B (tight coupling)
Eventing:     Servis A → Event → Broker → Trigger → Servis B (loose coupling)
```

| Bileşen | Görev |
|:--------|:------|
| **Source** | Event üretir (Kafka, API, cron, K8s API) |
| **Broker** | Event hub — üretici ile tüketici arasında tampon |
| **Trigger** | Broker'dan belirli event'leri filtreler ve hedefe iletir |
| **Channel** | Event iletim kanalı (InMemoryChannel, KafkaChannel) |
| **Sink** | Event'i alan hedef (Kubernetes Service, URL) |

---

## Kurulum

```bash
# Knative Eventing core
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/eventing-crds.yaml
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/eventing-core.yaml

# InMemoryChannel (geliştirme)
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/in-memory-channel.yaml

# MT-Channel-Based Broker
kubectl apply -f https://github.com/knative/eventing/releases/latest/download/mt-channel-broker.yaml

# Kafka backend (production)
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/latest/download/eventing-kafka-controller.yaml
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/latest/download/eventing-kafka-broker.yaml

# Durum kontrolü
kubectl get pods -n knative-eventing
```

---

## Broker & Trigger — Temel Pattern

```yaml
# 1. Broker oluştur (namespace başına)
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: default
  namespace: production
spec:
  config:
    apiVersion: v1
    kind: ConfigMap
    name: config-br-default-channel

---
# 2. Event Source — her dakika event üret
apiVersion: sources.knative.dev/v1
kind: PingSource
metadata:
  name: order-heartbeat
  namespace: production
spec:
  schedule: "*/1 * * * *"
  contentType: "application/json"
  data: '{"type": "health.check", "service": "orders"}'
  sink:
    ref:
      apiVersion: eventing.knative.dev/v1
      kind: Broker
      name: default

---
# 3. Trigger — belirli event'leri filtrele ve hedefe ilet
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: order-created-trigger
  namespace: production
spec:
  broker: default
  filter:
    attributes:
      type: order.created      # Sadece bu type'ı dinle
      source: /orders/service
  subscriber:
    ref:
      apiVersion: v1
      kind: Service
      name: inventory-service   # CloudEvent buraya POST edilir
```

---

## ApiServerSource — Kubernetes Event'lerini Dinle

K8s API olaylarını CloudEvent olarak yayınlar:

```yaml
apiVersion: sources.knative.dev/v1
kind: ApiServerSource
metadata:
  name: k8s-events-source
  namespace: production
spec:
  serviceAccountName: k8s-events-reader
  mode: Resource    # Resource (tam obje) veya Reference (sadece ref)
  resources:
  - apiVersion: v1
    kind: Pod
    controller: false
  - apiVersion: apps/v1
    kind: Deployment
  sink:
    ref:
      apiVersion: eventing.knative.dev/v1
      kind: Broker
      name: default

---
# RBAC — ApiServerSource için
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-events-reader
rules:
- apiGroups: [""]
  resources: [pods, events]
  verbs: [get, list, watch]
- apiGroups: [apps]
  resources: [deployments]
  verbs: [get, list, watch]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8s-events-reader
  namespace: production
```

---

## KafkaSource — Kafka'dan Event Tüketme

```yaml
apiVersion: sources.knative.dev/v1beta1
kind: KafkaSource
metadata:
  name: order-events
  namespace: production
spec:
  bootstrapServers:
  - kafka-broker.kafka:9092
  topics:
  - orders.created
  - orders.cancelled
  consumerGroup: knative-order-processor
  net:
    sasl:
      enable: true
      user:
        secretKeyRef:
          name: kafka-credentials
          key: username
      password:
        secretKeyRef:
          name: kafka-credentials
          key: password
  sink:
    ref:
      apiVersion: eventing.knative.dev/v1
      kind: Broker
      name: default
```

---

## CloudEvents Formatı

Knative Eventing, [CloudEvents v1.0](https://cloudevents.io) standardını kullanır:

```http
POST /
Content-Type: application/json
ce-specversion: 1.0
ce-type: order.created
ce-source: /orders/service
ce-id: 550e8400-e29b-41d4-a716-446655440000
ce-time: 2026-05-04T10:00:00Z
ce-datacontenttype: application/json

{
  "orderId": "ORD-123",
  "customerId": "CUST-456",
  "items": [{"sku": "PROD-789", "qty": 2}],
  "total": 49.99
}
```

```go
// Go'da CloudEvent üretme (cloudevents-sdk-go)
import cloudevents "github.com/cloudevents/sdk-go/v2"

event := cloudevents.NewEvent()
event.SetType("order.created")
event.SetSource("/orders/service")
event.SetData("application/json", map[string]interface{}{
    "orderId": "ORD-123",
})

c, _ := cloudevents.NewClientHTTP()
c.Send(ctx, event)
```

---

## Channel-Based Delivery — Dead Letter Queue

```yaml
apiVersion: messaging.knative.dev/v1
kind: Sequence
metadata:
  name: order-processing
  namespace: production
spec:
  channelTemplate:
    apiVersion: messaging.knative.dev/v1
    kind: InMemoryChannel    # veya KafkaChannel (production)
  steps:
  - ref:
      apiVersion: v1
      kind: Service
      name: validate-order
  - ref:
      apiVersion: v1
      kind: Service
      name: charge-payment
  - ref:
      apiVersion: v1
      kind: Service
      name: fulfill-order
  reply:
    ref:
      apiVersion: eventing.knative.dev/v1
      kind: Broker
      name: default
```

### Dead Letter Sink

```yaml
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: order-trigger
  namespace: production
spec:
  broker: default
  filter:
    attributes:
      type: order.created
  subscriber:
    ref:
      apiVersion: v1
      kind: Service
      name: order-processor
    uri: /process
  delivery:
    backoffDelay: PT2S        # İlk retry: 2 saniye sonra
    backoffPolicy: exponential
    retry: 5                  # 5 kere dene
    timeout: PT10S
    deadLetterSink:           # Tüm retry'lar başarısız olursa
      ref:
        apiVersion: v1
        kind: Service
        name: failed-events-logger
```

---

## Debug

```bash
# Broker durumu
kubectl get broker -n production
kubectl describe broker default -n production

# Trigger'lar
kubectl get trigger -n production
kubectl describe trigger order-created-trigger -n production

# Event flow izleme (soktest)
kubectl run event-display --image=gcr.io/knative-releases/knative.dev/eventing/cmd/event_display \
  --restart=Never -n production

# Trigger hedefini event-display'e yönlendir (test)
kubectl patch trigger order-created-trigger -n production \
  --type merge \
  -p '{"spec":{"subscriber":{"ref":{"name":"event-display","kind":"Service"}}}}'

kubectl logs event-display -n production -f
```

> [!TIP]
> Knative Eventing + Kafka backend kombinasyonu, RabbitMQ veya AWS SQS yerine Kubernetes-native event-driven mimari kurmak için 2026'da tercih edilen standarttır. `KafkaChannel` ile mesajlar kalıcı ve yeniden oynatılabilir olur.
