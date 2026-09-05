# Dinamik Kaynak Tahsisi (Dynamic Resource Allocation - DRA)

Kubernetes v1.31 sürümünde kararlı (GA) duruma gelen **Dynamic Resource Allocation (DRA)**, GPU, FPGA ve özel donanım kaynaklarını pod'lara tahsis etmek için kullanılan eski, basit sayısal limit tabanlı (`nvidia.com/gpu: 1` gibi) mekanizmaların yerine geçen çok daha akıllı ve esnek bir mimaridir.

---

## 1. Neden DRA?

Eski donanım tahsis yöntemi olan **Device Plugin** mimarisi ciddi kısıtlamalara sahipti. DRA ile bu kısıtlamalar aşılmıştır:

* **Eski Yöntem (Device Plugin):** Konteyner limitlerinde sadece sayısal talep yapılabilirdi (`nvidia.com/gpu: 1`). Ancak hangi marka, hangi özellik, ne kadar VRAM veya donanım topolojisi (örneğin NVLink bağlantılı) istendiği Kubernetes scheduler tarafından bilinemezdi. GPU ataması rastgele yapılırdı.
* **Yeni Yöntem (DRA):** Pod'un donanım talebi detaylı parametrelerle yapılabilir: *"Bana Tensor Core desteği olan, NVLink ile bağlı, minimum 40GB VRAM kapasitesine sahip bir GPU tahsis et."* DRA kontrolörleri bu kriterlere uyan en uygun donanımı tespit edip düğüm üzerinde rezerve eder.
* **Paylaşım Esnekliği:** Aynı fiziksel donanım, dinamik olarak birden fazla pod arasında daha ince kurallarla bölüştürülebilir.

---

## 2. Temel Kavramlar

DRA mimarisi dört temel bileşenden (nesneden) oluşur:

* **ResourceClass:** Hangi tür donanım kaynağının talep edildiğini tanımlayan global şablondur (Örn: GPU, FPGA).
* **DeviceClass:** Kaynak parametrelerini, kısıtlamalarını ve sürücü (driver) tanımlarını barındıran yapılandırma kümesidir.
* **ResourceClaim:** Pod'un talep ettiği donanım kaynağını ve özelliklerini içeren nesnedir.
* **ResourceClaimTemplate:** Pod şablonları (Deployment vb.) için kullanılan, her yeni pod ayağa kalktığında otomatik olarak o pod'a özel yeni bir `ResourceClaim` oluşturan şablon yapısıdır.

---

## 3. Örnek DRA Yapılandırması ve Kullanımı (YAML)

Aşağıdaki adımlarda bir GPU sınıfı tanımlanmakta ve bu sınıfa uygun bir talep ile pod ayağa kaldırılmaktadır:

### Step 1: ResourceClass ve DeviceClass Tanımlama

Küme yöneticisi tarafından desteklenen donanım sınıfı ve sürücü (driver) tanımlanır:

```yaml
apiVersion: resource.k8s.io/v1alpha2
kind: ResourceClass
metadata:
  name: nvidia-h100-gpu
driverName: gpu.nvidia.com
parametersRef:
  kind: ConfigMap
  name: h100-parameters
suitableNodes:
  nodeSelectorTerms:
    - matchExpressions:
        - key: nvidia.com/gpu.product
          operator: In
          values:
            - NVIDIA-H100-SXM5-80GB
```

### Step 2: Pod Seviyesinde Donanım Talep Etme

Geliştirici veya veri bilimci, talep edeceği kaynağı `ResourceClaim` ile belirtir ve pod içindeki konteynere bağlar:

```yaml
apiVersion: resource.k8s.io/v1alpha2
kind: ResourceClaim
metadata:
  name: my-gpu-claim
  namespace: ml-training
spec:
  resourceClassName: nvidia-h100-gpu
---
apiVersion: v1
kind: Pod
metadata:
  name: ml-training-pod
  namespace: ml-training
spec:
  restartPolicy: OnFailure
  containers:
    - name: cuda-trainer
      image: pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime
      command: ["python", "-c", "import torch; print('CUDA Devices:', torch.cuda.device_count())"]
      resources:
        claims:
          - name: gpu-claim
  resourceClaims:
    - name: gpu-claim
      source:
        resourceClaimName: my-gpu-claim
```

---

## 4. İzleme, Teşhis ve Sorun Giderme

DRA ile yapılan atamaları ve durumlarını izlemek için aşağıdaki komutlardan yararlanılır:

```bash
# ResourceClaim durumunu kontrol etme
kubectl get resourceclaims -n ml-training

# Hangi donanımın hangi pod'a ve düğüme tahsis edildiğini detaylı inceleme
kubectl describe resourceclaim my-gpu-claim -n ml-training
# Çıktı Özeti:
# Allocation:
#   NodeName: gpu-node-01
#   ResourceHandle: nvidia-h100-uuid-abc123xyz

# Donanım sürücüsü (DRA driver) loglarını okuma
kubectl logs -n kube-system -l app=nvidia-dra-driver

# Bekleyen (Pending) veya atanamayan donanım taleplerini inceleme
kubectl get events -n ml-training | grep -i ResourceClaim
```

---

## 5. Device Plugin vs. DRA Karşılaştırma Tablosu

| Özellik | Device Plugin (Eski Mimari) | DRA (Yeni Mimari - v1.31+) |
| :--- | :--- | :--- |
| **Talep Yöntemi** | `resources.limits` altına sadece adet yazılır | `ResourceClaim` ve parametre tabanlı |
| **Donanım Özellik Seçimi** | ❌ Yapılamaz (Gelen GPU rastgele atanır) | ✅ Yapılabilir (CEL expression, VRAM, NVLink seçimi) |
| **Dinamik Paylaşım** | ❌ Sürücü seviyesinde statik yapılandırma | ✅ API üzerinden dinamik kontrol |
| **Topoloji Farkındalığı** | ❌ Kısıtlı | ✅ Tam uyumlu (PCIe, NUMA, NVLink yapısına göre yerleşim) |
| **Kubernetes Sürümü** | v1.10+ | **v1.31 (GA)** |

---

## Özet

Dynamic Resource Allocation (DRA), Kubernetes üzerinde yapay zeka (AI/ML) eğitimleri ve yüksek performanslı hesaplama (HPC) iş yükleri koşturan ekipler için devrim niteliğinde bir yeniliktir. Sayısal limitlerden özellik tabanlı talep modeline geçiş, pahalı GPU donanımlarının çok daha verimli, güvenli ve esnek kullanılmasını sağlar.
