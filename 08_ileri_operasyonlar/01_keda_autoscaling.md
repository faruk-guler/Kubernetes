# KEDA — Olay Tabanlı Otomatik Ölçeklendirme

## 1.1 KEDA Nedir?

Standart Kubernetes HPA yalnızca CPU ve RAM'e göre ölçeklendirir. **KEDA (Kubernetes Event-driven Autoscaling)** ise kuyruktaki mesaj sayısına, HTTP istek hızına, veritabanı yüküne veya neredeyse herhangi bir metriğe göre ölçeklendirme yapar. Dahası Scale-to-Zero (0 pod) desteği sunar.

```bash
# KEDA kurulumu
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace
```

## 1.2 ScaledObject Örnekleri

### RabbitMQ Kuyruğuna Göre

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-processor-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: order-processor-deployment
  pollingInterval: 15       # Her 15 saniyede kontrol et
  cooldownPeriod: 300       # Ölçek küçültme için 5 dakika bekle
  minReplicaCount: 0        # Kuyruk boşken sıfır pod
  maxReplicaCount: 50
  triggers:
  - type: rabbitmq
    metadata:
      protocol: amqp
      queueName: orders
      mode: QueueLength
      value: "20"           # Her 20 mesaj için 1 pod
    authenticationRef:
      name: rabbitmq-trigger-auth
```

### Kafka'ya Göre

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
spec:
  scaleTargetRef:
    name: kafka-consumer
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.production:9092
      consumerGroup: my-consumer-group
      topic: events
      lagThreshold: "100"   # Her 100 lag için 1 pod
      offsetResetPolicy: latest
```

### HTTP İsteklerine Göre (KEDA HTTP Addon)

```yaml
apiVersion: http.keda.sh/v1alpha1
kind: HTTPScaledObject
metadata:
  name: web-app-http-scaler
spec:
  hosts:
  - myapp.example.com
  targetPendingRequests: 100
  scaledownPeriod: 300
  scaleTargetRef:
    deployment: web-app
    service: web-app-svc
    port: 80
  replicas:
    min: 0
    max: 20
```

### Prometheus Metriğine Göre

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: prometheus-scaler
spec:
  scaleTargetRef:
    name: my-app
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring:9090
      metricName: http_requests_total
      threshold: "100"      # RPS 100'ü geçince ölçeklendir
      query: sum(rate(http_requests_total{app="my-app"}[2m]))
```

## 1.3 Authentication (Kimlik Doğrulama)

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: rabbitmq-trigger-auth
  namespace: production
spec:
  secretTargetRef:
  - parameter: host
    name: rabbitmq-secret
    key: RABBITMQ_URL
```

> [!TIP]
> KEDA'nın Scale-to-Zero özelliği, gece saatlerinde kullanılmayan batch işlem pod'larını tamamen kapatarak cluster kaynakları ve maliyeti önemli ölçüde düşürür. Kubecost ile ölçüp optimize edebilirsiniz.

---
