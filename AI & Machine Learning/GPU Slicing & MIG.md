# GPU Slicing & MIG — Kubernetes'te GPU Yönetimi

AI/ML workload'ları için GPU pahalı bir kaynaktır. Kubernetes'te GPU'yu birden fazla pod'a paylaştırmanın iki yolu vardır: **Time-Slicing** (tüm GPU'ya sırayla erişim) ve **MIG** (Multi-Instance GPU — donanımsal bölümleme).

---

## GPU Kaynakları Kubernetes'te

```yaml
# Basit GPU isteği
spec:
  containers:
  - name: training
    resources:
      limits:
        nvidia.com/gpu: 1     # Tam 1 GPU
```

```bash
# Node'lardaki GPU'ları görüntüle
kubectl get nodes -o json | jq '.items[] | 
  {name: .metadata.name, 
   gpus: .status.capacity["nvidia.com/gpu"]}'
```

---

## NVIDIA Device Plugin Kurulumu

```bash
# NVIDIA GPU Operator (önerilen — her şeyi otomatik kurar)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgmExporter.enabled=true    # GPU metrikleri

# Kurulum doğrula
kubectl get pods -n gpu-operator
kubectl describe node <gpu-node> | grep -A10 "Allocatable"
# nvidia.com/gpu: 8
```

---

## Time-Slicing (GPU Paylaşımı)

Tek GPU'yu birden fazla pod'un sırayla kullanması. MIG desteklemeyen GPU'larda kullanılır (örn: T4, A10G):

```yaml
# ConfigMap: GPU'yu 4 dilime böl
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 4        # 1 GPU → 4 sanal GPU
```

```bash
# ConfigMap'i GPU Operator'a bağla
kubectl patch clusterpolicy gpu-cluster-policy \
  -n gpu-operator \
  --type merge \
  -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config"}}}}'

# Sonuç: Her node 8 GPU varsa → 32 "nvidia.com/gpu" görünür
kubectl get node <gpu-node> -o json | \
  jq '.status.capacity["nvidia.com/gpu"]'
# "32"
```

```yaml
# Dilimlenmiş GPU kullanan pod
spec:
  containers:
  - name: inference
    image: company/inference:v1
    resources:
      limits:
        nvidia.com/gpu: 1    # 1/4 GPU kapasitesi alır
```

---

## MIG — Multi-Instance GPU (A100, H100)

NVIDIA A100/H100 GPU'ları donanımsal olarak bağımsız parçalara bölünebilir. Her parça kendi belleği ve compute'una sahiptir:

```
A100 (80GB) MIG profilleri:
  1g.10gb  → 1/7 GPU, 10GB bellek (7 instance)
  2g.20gb  → 2/7 GPU, 20GB bellek (3 instance + 1 1g)
  3g.40gb  → 3/7 GPU, 40GB bellek (2 instance)
  7g.80gb  → Tam GPU
```

```bash
# Node'da MIG etkinleştir
kubectl label node <gpu-node> nvidia.com/mig.config=all-1g.10gb

# MIG stratejisini ayarla (single veya mixed)
kubectl patch clusterpolicy gpu-cluster-policy \
  -n gpu-operator \
  --type merge \
  -p '{"spec":{"mig":{"strategy":"mixed"}}}'

# MIG profilleri görünür mü?
kubectl get node <gpu-node> -o json | jq '.status.capacity' | grep mig
# "nvidia.com/mig-1g.10gb": "7"
# "nvidia.com/mig-2g.20gb": "0"
```

```yaml
# MIG instance kullanan pod
spec:
  containers:
  - name: small-model
    resources:
      limits:
        nvidia.com/mig-1g.10gb: 1    # 10GB MIG instance
  - name: large-model
    resources:
      limits:
        nvidia.com/mig-3g.40gb: 1    # 40GB MIG instance
```

---

## Node Seçimi (GPU Tipi)

```yaml
# Belirli GPU tipine yönlendir
spec:
  nodeSelector:
    nvidia.com/gpu.product: "A100-SXM4-80GB"

# veya affinity ile
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: nvidia.com/gpu.memory
          operator: Gt
          values: ["40000"]    # 40GB+ GPU
```

---

## GPU Metrikleri (DCGM Exporter)

```promql
# GPU kullanım oranı
DCGM_FI_DEV_GPU_UTIL{namespace="production"}

# GPU bellek kullanımı
DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE

# GPU sıcaklığı
DCGM_FI_DEV_GPU_TEMP > 85    # Uyarı: 85°C üzeri

# SM (Streaming Multiprocessor) doluluk
DCGM_FI_DEV_SM_CLOCK

# Pod bazlı GPU kullanımı
DCGM_FI_DEV_GPU_UTIL * on(gpu, UUID) 
  group_left(pod, namespace) 
  DCGM_FI_DEV_GPU_UTIL{pod!=""}
```

---

## DRA ile GPU Tahsisi (K8s 1.31+ GA)

Dynamic Resource Allocation, GPU gibi özel donanımları daha esnek yönetir:

```yaml
apiVersion: resource.k8s.io/v1alpha3
kind: ResourceClaim
metadata:
  name: gpu-claim
  namespace: production
spec:
  devices:
    requests:
    - name: gpu
      deviceClassName: nvidia-gpu
      selectors:
      - cel:
          expression: device.attributes["memory"].isGreaterThan(quantity("20Gi"))
---
apiVersion: v1
kind: Pod
spec:
  resourceClaims:
  - name: gpu
    resourceClaimName: gpu-claim
  containers:
  - name: training
    resources:
      claims:
      - name: gpu
```

> [!TIP]
> **Ne zaman ne kullan:**
> - Az sayıda büyük iş → Tam GPU (1 pod = 1 GPU)
> - Küçük inference servisleri → Time-Slicing (1 GPU = 4-8 pod)
> - Kritik, izole ihtiyaç → MIG (her bölüm garantili bellek)

> [!WARNING]
> Time-slicing'de GPU belleği paylaşılmaz, zaman paylaşılır. Bir pod çok bellek kullanırsa `CUDA out of memory` hatası alır. MIG'de her bölümün kendi garantili belleği var.
