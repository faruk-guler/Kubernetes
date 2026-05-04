# KEDA — Kubernetes Event-Driven Autoscaling

KEDA, HTTP istek sayısı veya CPU/bellek gibi metriklerin ötesinde — Kafka topic lag, RabbitMQ kuyruk uzunluğu, AWS SQS, Prometheus sorgusu ve 60+ event kaynağına göre pod'ları otomatik ölçeklendirir. HPA'yı genişletir, yerini almaz.

---

## KEDA vs HPA

```
HPA:
  Kaynak: CPU, Memory, custom metric
  Minimum: 1 pod (sıfıra inemez)
  
KEDA:
  Kaynak: Kafka, SQS, RabbitMQ, Cron, HTTP, Prometheus, Redis, 60+
  Minimum: 0 pod (event yoksa tamamen kapat → maliyet tasarrufu)
  HPA oluşturur — birbirleriyle çelişmez
```

---

## Kurulum

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set prometheus.metricServer.enabled=true \
  --set prometheus.operator.enabled=true
```

---

## ScaledObject — Temel Yapı

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: api-scaler
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicaCount: 0      # Sıfıra inebilir
  maxReplicaCount: 50
  cooldownPeriod: 300     # Scale-down sonrası bekleme (saniye)
  pollingInterval: 15     # Metrik kontrol sıklığı
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring:9090
      metricName: http_requests_total
      query: |
        sum(rate(http_requests_total{app="api"}[2m]))
      threshold: "100"    # Pod başına 100 req/s
```

---

## Kafka Topic Lag

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: order-consumer
  minReplicaCount: 1
  maxReplicaCount: 20
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.production:9092
      consumerGroup: order-processing-group
      topic: orders
      lagThreshold: "50"        # Consumer başına max 50 mesaj lag
      offsetResetPolicy: latest
    authenticationRef:
      name: kafka-auth
---
# SASL/TLS kimlik doğrulama
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: kafka-auth
  namespace: production
spec:
  secretTargetRef:
  - parameter: username
    name: kafka-secret
    key: username
  - parameter: password
    name: kafka-secret
    key: password
```

---

## AWS SQS Kuyruğu

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: email-worker
  minReplicaCount: 0
  maxReplicaCount: 30
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.eu-west-1.amazonaws.com/123456/email-queue
      queueLength: "10"     # Pod başına max 10 mesaj
      awsRegion: eu-west-1
    authenticationRef:
      name: aws-irsa-auth
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-irsa-auth
  namespace: production
spec:
  podIdentity:
    provider: aws    # IRSA — ServiceAccount üzerinden
```

---

## Cron Bazlı Ölçekleme

```yaml
# Mesai saatlerinde büyük, gece küçük
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: business-hours-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: web-app
  triggers:
  - type: cron
    metadata:
      timezone: Europe/Istanbul
      start: "0 8 * * 1-5"     # Haftaiçi 08:00 → scale up
      end:   "0 19 * * 1-5"    # Haftaiçi 19:00 → scale down
      desiredReplicas: "20"
  - type: cron
    metadata:
      timezone: Europe/Istanbul
      start: "0 19 * * 1-5"
      end:   "0 8 * * 1-5"
      desiredReplicas: "3"
```

---

## Redis List / Stream

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: redis-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: job-worker
  minReplicaCount: 0
  maxReplicaCount: 15
  triggers:
  - type: redis
    metadata:
      address: redis.production:6379
      listName: job-queue
      listLength: "5"     # Pod başına max 5 item
    authenticationRef:
      name: redis-auth
```

---

## HTTP Tabanlı Ölçekleme (KEDA HTTP Addon)

```bash
# HTTP addon kurulumu
helm install http-add-on kedacore/keda-add-ons-http \
  --namespace keda
```

```yaml
apiVersion: http.keda.sh/v1alpha1
kind: HTTPScaledObject
metadata:
  name: web-http-scaler
  namespace: production
spec:
  hosts:
  - app.company.com
  targetPendingRequests: 100    # Pod başına max 100 pending req
  scaleTargetRef:
    name: web-app
    kind: Deployment
    apiVersion: apps/v1
    service: web-service
    port: 80
  replicas:
    min: 0
    max: 30
```

---

## İzleme

```bash
# ScaledObject durumu
kubectl get scaledobject -n production
# NAME               SCALETARGETKIND   SCALETARGETNAME   MIN  MAX  READY  ACTIVE
# kafka-consumer     Deployment        order-consumer    1    20   True   True

# Mevcut replica sayısı
kubectl get hpa -n production   # KEDA, arka planda HPA oluşturur

# KEDA operator logları
kubectl logs -n keda -l app=keda-operator --tail=50

# ScaledObject detayı
kubectl describe scaledobject kafka-consumer-scaler -n production
```

```promql
# KEDA metrik sunucu sorguları
keda_scaler_metrics_value             # Ölçekleme kararı verilen metrik
keda_scaler_active                    # ScaledObject aktif mi?
keda_scaled_object_paused             # Duraklatılmış mı?
```

> [!TIP]
> `minReplicaCount: 0` ile gece saatlerinde hiç yük olmayan servisleri tamamen kapatabilirsin. Bir Kafka consumer veya SQS worker için bu %60-80 node maliyeti tasarrufu anlamına gelir.
