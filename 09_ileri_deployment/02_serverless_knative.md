# Serverless ve Knative

## 2.1 Neden Kubernetes Üzerinde Serverless?

2026'da her uygulamanın 7/24 çalışmasına gerek yoktur. Sadece trafik geldiğinde ayağa kalkan, trafik bittiğinde 0'a inen yapılar maliyet ve kaynak verimliliği açısından kritiktir.

| Özellik | Normal Deployment | Knative |
|:---|:---:|:---:|
| Standby maliyeti | Var | Yok (Scale-to-zero) |
| Otomatik ölçekleme | HPA/KEDA | Dahili |
| Revision yönetimi | Manuel | Otomatik |
| Traffic splitting | Ayrı araç | Dahili |

## 2.2 Knative Kurulumu

```bash
# Knative Serving CRD'leri
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-core.yaml

# Cilium ile ağ katmanı
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.15.0/kourier.yaml
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# Knative Eventing
kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.15.0/eventing-crds.yaml
kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.15.0/eventing-core.yaml
```

## 2.3 Knative Service (Scale-to-Zero)

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: image-processor
  namespace: production
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: "0"    # 0'a kadar ölçeklendir
        autoscaling.knative.dev/max-scale: "20"   # Maksimum 20 pod
        autoscaling.knative.dev/target: "100"     # Her pod 100 concurrent istek
    spec:
      containers:
      - image: my-registry/image-processor:v1.0.0
        env:
        - name: TARGET
          value: "Kubernetes 2026"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
```

60 saniye boyunca istek gelmezse pod'lar otomatik kapatılır. İlk istek geldiğinde saniyeler içinde ayağa kalkar.

## 2.4 Traffic Splitting

```yaml
# Knative ile %90/%10 traffic split
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: web-app
spec:
  traffic:
  - latestRevision: false
    revisionName: web-app-v1
    percent: 90
  - latestRevision: true
    percent: 10
    tag: canary
```

## 2.5 Knative Eventing

Uygulamaların olaylar üzerinden birbirleriyle haberleşmesi:

```yaml
# Event Broker
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: default
  namespace: production

---
# Event Source (S3'te dosya yüklenince event üret)
apiVersion: sources.knative.dev/v1
kind: ApiServerSource
metadata:
  name: k8s-events
spec:
  serviceAccountName: events-sa
  mode: Resource
  resources:
  - apiVersion: v1
    kind: Event
  sink:
    ref:
      apiVersion: eventing.knative.dev/v1
      kind: Broker
      name: default

---
# Trigger (event'i ilgili servise yönlendir)
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: image-processor-trigger
spec:
  broker: default
  filter:
    attributes:
      type: com.example.image.uploaded
  subscriber:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: image-processor
```

> [!TIP]
> Knative, KEDA ile birlikte kullanıldığında ideal bir kombinasyon oluşturur: KEDA Kafka/RabbitMQ gibi kaynaklara göre ölçeklenirken, Knative HTTP tabanlı servisleri yönetir.

