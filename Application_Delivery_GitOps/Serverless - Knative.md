# Serverless ve Knative

## Neden Kubernetes Üzerinde Serverless?

2026'da her uygulamanın 7/24 çalışmasına gerek yoktur. Sadece trafik geldiğinde ayağa kalkan, trafik bittiğinde 0'a inen yapılar maliyet ve kaynak verimliliği açısından kritiktir.

| Özellik | Normal Deployment | Knative |
|:---|:---:|:---:|
| Standby maliyeti | Var | Yok (Scale-to-zero) |
| Otomatik ölçekleme | HPA/KEDA | Dahili |
| Revision yönetimi | Manuel | Otomatik |
| Traffic splitting | Ayrı araç | Dahili |

## Knative Kurulumu

> [!NOTE]
> Aşağıdaki örnekler `v1.16.0` sürümü üzerinden gösterilmektedir. Kurulum öncesi güncel sürümü kontrol edin: `https://github.com/knative/serving/releases`

```bash
KNATIVE_VERSION="v1.16.0"

# Knative Serving CRD'leri
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml

# Ağ katmanı: Kourier (hafif) veya Istio/Contour seçilebilir
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# Knative Eventing (opsiyonel)
kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-crds.yaml
kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml

# Kurulum doğrulama
kubectl get pods -n knative-serving
kubectl get pods -n knative-eventing
```

## Knative Service (Scale-to-Zero)

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

## Traffic Splitting

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

## Knative Eventing

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
