# HPA, VPA ve Cluster Autoscaling

## 5.1 Ölçeklendirme Katmanları

Kubernetes'te 3 katmanlı bir ölçeklendirme mimarisi vardır:

```
┌─────────────────────────────────────────────┐
│  Cluster Autoscaler (Node ekle/kaldır)       │
│  ┌───────────────────────────────────────┐   │
│  │  HPA (Pod sayısı artır/azalt)         │   │
│  │  ┌─────────────────────────────────┐  │   │
│  │  │  VPA (Pod kaynakları optimize)  │  │   │
│  │  └─────────────────────────────────┘  │   │
│  └───────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

## 5.2 Ön Koşul: Metrics Server

HPA ve VPA'nın çalışabilmesi için **Metrics Server** kurulu olmalıdır:

```bash
# Kurulum
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# RKE2 / Self-signed sertifika ortamında (--kubelet-insecure-tls gerekebilir)
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Doğrulama
kubectl top nodes
kubectl top pods -A
```

## 5.3 HPA (Horizontal Pod Autoscaler)

### CPU Tabanlı HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70    # Ortalama CPU %70 geçince scale-out
  - type: Resource
    resource:
      name: memory
      target:
        type: AverageValue
        averageValue: 500Mi       # Ortalama 500Mi geçince scale-out
```

### Özel Metrik ile HPA (KEDA Olmadan)

```yaml
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "100"       # Pod başına 100 RPS
```

### Ölçeklendirme Davranışı (Behavior)

```yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300     # 5 dakika bekle (oscillation önler)
      policies:
      - type: Percent
        value: 25                          # Her 15s'de en fazla %25 küçül
        periodSeconds: 15
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Pods
        value: 4                           # Her 15s'de en fazla 4 pod ekle
        periodSeconds: 15
      - type: Percent
        value: 100                         # Veya %100 artır
        periodSeconds: 60
      selectPolicy: Max                    # Hangisi daha fazlaysa onu uygula
```

### kubectl ile HPA Yönetimi

```bash
# HPA oluştur (imperative)
kubectl autoscale deployment web-app --cpu-percent=70 --min=2 --max=20

# HPA durumu
kubectl get hpa
kubectl describe hpa web-app-hpa

# Canlı takip
kubectl get hpa web-app-hpa --watch
```

> [!IMPORTANT]
> HPA'nın çalışması için pod'larda **`resources.requests`** tanımlı olmalıdır. Yoksa Metrics Server kullanım yüzdesini hesaplayamaz.

## 5.4 VPA (Vertical Pod Autoscaler)

VPA, pod sayısını değil pod'un **boyutunu** (CPU/RAM requests/limits) otomatik optimize eder.

### VPA Kurulumu

```bash
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
```

### VPA YAML

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web-app-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  updatePolicy:
    updateMode: "Off"             # Önce öneri modunda çalıştır
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 4
        memory: 8Gi
```

### VPA Önerilerini Okuma

```bash
kubectl describe vpa web-app-vpa
```

Çıktıda dikkat edilecek alanlar:
- **Target:** VPA'nın ideal gördüğü değer
- **Lower Bound:** Minimum güvenli değer
- **Upper Bound:** Maksimum güvenli değer

### VPA Modları

| Mod | Davranış |
|:---|:---|
| `Off` | Sadece öneri üretir, değişiklik yapmaz (başlangıç için ÖNERILIR) |
| `Initial` | Sadece pod ilk oluşturulduğunda uygular |
| `Recreate` | Değer değişince pod'u yeniden başlatır |
| `Auto` | Recreate ile aynı (varsayılan) |

> [!WARNING]
> HPA ve VPA'yı aynı kaynak (CPU) için birlikte kullanmayın — birbirleriyle çakışır. HPA için dış metrikler (KEDA), VPA için CPU/RAM kullanmak iyi bir kombinasyondur.

## 5.5 Cluster Autoscaler

Node sayısını otomatik artıran/azaltan bileşen:

```yaml
# AWS (EKS) örneği
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - command:
        - ./cluster-autoscaler
        - --cloud-provider=aws
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/my-cluster
        - --scale-down-unneeded-time=10m      # 10 dk boşsa kapat
        - --scale-down-utilization-threshold=0.5  # %50 altında boşsa
        - --skip-nodes-with-local-storage=false
        name: cluster-autoscaler
```

> [!TIP]
> 2026 standartlarında Cluster Autoscaler'ın modern halkası olan **Karpenter** (AWS) veya **KEDA HTTP Addon** tercih edilmektedir. Karpenter, node başlatma süresini 60 saniyeden 15 saniyeye düşürür.

---
