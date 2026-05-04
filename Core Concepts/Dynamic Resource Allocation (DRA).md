# Dynamic Resource Allocation (DRA)

Kubernetes 1.31'de GA olan DRA, GPU ve özel donanım kaynaklarını Pod'lara tahsis etmek için `nvidia.com/gpu: 1` gibi basit sayısal limitlerden çok daha akıllı bir mekanizma sunar.

---

## Neden DRA?

```
Eski yöntem (Device Plugin):
  resources:
    limits:
      nvidia.com/gpu: 1    # Sadece sayı — hangi GPU? hangi özellik? bilinmez

DRA:
  Talep: "Tensor Core desteğli, NVLink bağlantılı, 40GB+ VRAM olan bir GPU"
  Atama: DRA scheduler bu özelliklere uyan GPU'yu bulup tahsis eder
  Paylaşım: Aynı GPU birden fazla Pod'a bölünebilir (MIG benzeri ama daha esnek)
```

---

## Temel Kavramlar

```
ResourceClass      → Hangi tür kaynak? (GPU, FPGA, özel donanım)
ResourceClaim      → Pod'un kaynak talebi
ResourceClaimTemplate → Şablon — her pod kendi claim'ini oluşturur
DeviceClass        → Kaynak parametreleri ve kısıtlamaları
```

---

## ResourceClass Tanımı

```yaml
apiVersion: resource.k8s.io/v1alpha3
kind: ResourceClass
metadata:
  name: gpu-class
driverName: gpu.nvidia.com    # DRA driver (node'larda çalışır)
parametersRef:
  apiGroup: gpu.resource.nvidia.com
  kind: GpuClaimParameters
  name: default-gpu-params
```

---

## DeviceClass (1.31+)

```yaml
apiVersion: resource.k8s.io/v1alpha3
kind: DeviceClass
metadata:
  name: nvidia-h100
spec:
  selectors:
  - cel:
      expression: device.driver == "gpu.nvidia.com" &&
                  device.attributes["memory"].quantity >= "80Gi" &&
                  device.attributes["model"].string == "H100"
  config:
  - opaque:
      driver: gpu.nvidia.com
      parameters:
        apiVersion: gpu.nvidia.com/v1
        kind: GpuConfig
        sharing:
          strategy: TimeSlicing
          timeSlicingConfig:
            interval: Default
```

---

## ResourceClaim (Pod ile Birlikte)

```yaml
# Yöntem 1: Bağımsız ResourceClaim
apiVersion: resource.k8s.io/v1alpha3
kind: ResourceClaim
metadata:
  name: my-gpu-claim
  namespace: ml-training
spec:
  devices:
    requests:
    - name: gpu
      deviceClassName: nvidia-h100
      count: 1    # 1 H100 GPU talep et
```

```yaml
# Pod'da claim'i kullan
apiVersion: v1
kind: Pod
metadata:
  name: training-job
  namespace: ml-training
spec:
  resourceClaims:
  - name: gpu              # Pod içinde bu isimle erişilir
    resourceClaimName: my-gpu-claim

  containers:
  - name: trainer
    image: ghcr.io/company/trainer:v1
    resources:
      claims:
      - name: gpu          # Hangi claim'i kullanacak?
    env:
    - name: CUDA_VISIBLE_DEVICES
      value: "0"
```

---

## ResourceClaimTemplate (Her Pod Kendi GPU'sunu Alır)

```yaml
apiVersion: resource.k8s.io/v1alpha3
kind: ResourceClaimTemplate
metadata:
  name: gpu-template
  namespace: ml-training
spec:
  spec:
    devices:
      requests:
      - name: gpu
        deviceClassName: nvidia-h100
        count: 1

---
# Deployment'ta template kullan
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-fleet
  namespace: ml-training
spec:
  replicas: 4    # 4 pod → her biri kendi H100'ünü alır
  template:
    spec:
      resourceClaims:
      - name: gpu
        resourceClaimTemplateName: gpu-template    # Template'den oluştur
      containers:
      - name: inference
        image: ghcr.io/company/inference:v2
        resources:
          claims:
          - name: gpu
```

---

## Çoklu Kaynak Talebi

```yaml
apiVersion: resource.k8s.io/v1alpha3
kind: ResourceClaim
metadata:
  name: multi-device-claim
  namespace: ml-training
spec:
  devices:
    requests:
    - name: gpu-0
      deviceClassName: nvidia-h100
      count: 1
    - name: gpu-1
      deviceClassName: nvidia-h100
      count: 1
    constraints:
    - requests: [gpu-0, gpu-1]
      matchAttribute: "gpu.nvidia.com/nv-link-domain"
      # İki GPU NVLink ile bağlı olmalı — multi-GPU training için
```

---

## Structured Parameters ile GPU Paylaşımı

```yaml
# Aynı GPU'yu iki pod paylaşabilir (zaman dilimleme)
apiVersion: resource.k8s.io/v1alpha3
kind: ResourceClaim
metadata:
  name: shared-gpu-claim
spec:
  devices:
    requests:
    - name: gpu
      deviceClassName: nvidia-a100-mig
      allocationMode: All    # Available | All | ExactCount

---
# MIG ile 7 pod, tek A100'ü paylaşır
# A100 MIG 1g.5gb: 7 adet slice
apiVersion: resource.k8s.io/v1alpha3
kind: DeviceClass
metadata:
  name: nvidia-a100-mig-1g
spec:
  selectors:
  - cel:
      expression: |
        device.driver == "gpu.nvidia.com" &&
        device.attributes["mig-profile"].string == "1g.5gb"
```

---

## İzleme ve Sorun Giderme

```bash
# ResourceClaim durumu
kubectl get resourceclaims -n ml-training
# NAME             ALLOCATIONMODE   STATE        AGE
# my-gpu-claim     WaitForFirstConsumer  Allocated  5m

# Hangi node'a tahsis edildi?
kubectl describe resourceclaim my-gpu-claim -n ml-training
# Allocation:
#   NodeName: gpu-node-01
#   ResourceHandle: nvidia-h100-uuid-xxx

# DRA driver logları
kubectl logs -n kube-system -l app=nvidia-dra-driver

# Pending resourceclaim sorunları
kubectl get events -n ml-training | grep ResourceClaim
```

---

## Device Plugin vs DRA Karşılaştırması

| Özellik | Device Plugin (eski) | DRA (yeni) |
|:--------|:---------------------|:-----------|
| Talep yöntemi | `resources.limits` sayısı | ResourceClaim CRD |
| Donanım seçimi | Yok (rastgele) | CEL expression ile özellik bazlı |
| Paylaşım | Sınırlı | Yapılandırılabilir |
| Multi-GPU topoloji | Yok | NVLink, PCIe domain kısıtı |
| Kubernetes versiyonu | 1.10+ | **1.31 GA** |

> [!TIP]
> DRA 2026'da NVIDIA, Intel ve AMD tarafından aktif olarak destekleniyor. Yeni GPU cluster'ları için Device Plugin yerine DRA sürücülerini tercih edin — çok daha granüler ve esnek kaynak yönetimi sağlar.
