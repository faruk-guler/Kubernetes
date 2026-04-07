# AI/ML ve Kubernetes — GPU İş Yükleri

## 1.1 Kubernetes ve Yapay Zeka

2026 yılı yapay zekanın olgunluk yılıdır. Kubernetes, AI/ML iş yüklerini (Training ve Inference) çalıştırmak için en ideal platformdur çünkü:

- GPU'ları pod'lar arasında paylaştırabilir
- Büyük model eğitimini birden fazla node'a dağıtabilir
- Auto-scaling ile inference maliyetini optimize eder
- GitOps ile model deployment'ları versiyonlanır

## 1.2 GPU Yönetimi

```bash
# NVIDIA Device Plugin kurulumu
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml

# GPU node'larını gör
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpu: .status.capacity["nvidia.com/gpu"]}'
```

### GPU Pod Tanımı

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-training-job
spec:
  containers:
  - name: trainer
    image: nvcr.io/nvidia/pytorch:24.01-py3
    resources:
      limits:
        nvidia.com/gpu: 2          # 2 GPU talep et
      requests:
        nvidia.com/gpu: 2
    volumeMounts:
    - name: model-storage
      mountPath: /models
  volumes:
  - name: model-storage
    persistentVolumeClaim:
      claimName: model-pvc
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

### GPU MIG (Multi-Instance GPU) — 2026 Standardı

```yaml
# Tek A100 GPU'yu 7 küçük instance'a böl
# NVIDIA MIG yapılandırması node label'ı üzerinden
spec:
  containers:
  - name: inference
    resources:
      limits:
        nvidia.com/mig-1g.10gb: 1   # 1/7 GPU (10GB)
```

## 1.3 Kubeflow — ML İş Akışları

```bash
# Kubeflow kurulumu (kustomize ile)
export PIPELINE_VERSION=2.1.0
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$PIPELINE_VERSION"
```

**Kubeflow Pipeline Örneği:**

```python
from kfp import dsl

@dsl.component
def preprocess(data_path: str) -> str:
    # Veri temizleme
    return processed_path

@dsl.component
def train(data_path: str, epochs: int) -> str:
    # Model eğitimi
    return model_path

@dsl.pipeline(name="ml-pipeline")
def ml_pipeline(data_path: str = "gs://my-bucket/data"):
    preprocess_task = preprocess(data_path=data_path)
    train_task = train(
        data_path=preprocess_task.output,
        epochs=100
    )
```

## 1.4 KServe — Model Servis Etme (Inference)

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llm-service
  namespace: production
spec:
  predictor:
    model:
      modelFormat:
        name: pytorch
      storageUri: "pvc://model-pvc/llama-3-8b"
      resources:
        limits:
          nvidia.com/gpu: 1
    minReplicas: 1
    maxReplicas: 5
  transformer:               # İsteği model formatına dönüştür
    containers:
    - name: transformer
      image: my-registry/llm-transformer:v1.0
```

## 1.5 LLM ve vLLM — 2026'nın En Güncel Trendi

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-server
  namespace: ai-production
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        args:
        - "--model"
        - "meta-llama/Llama-3-8B-Instruct"
        - "--tensor-parallel-size"
        - "1"
        - "--max-model-len"
        - "8192"
        - "--served-model-name"
        - "llama-3-8b"
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "24Gi"
        ports:
        - containerPort: 8000
          name: http
```

**vLLM API kullanımı:**

```bash
curl http://vllm-service.ai-production:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "llama-3-8b", "messages": [{"role": "user", "content": "Kubernetes 2026 nedir?"}]}'
```

## 1.6 KEDA ile LLM Autoscaling

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: vllm-scaler
spec:
  scaleTargetRef:
    name: vllm-server
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring:9090
      query: sum(vllm:request_queue_size)
      threshold: "10"          # Kuyruktaki her 10 istek için 1 pod ekle
```

> [!TIP]
> GPU node'ları pahalıdır. KEDA ile scale-to-minimum (1 pod) yapıp yüklenince scale-out yaparak GPU maliyetleri önemli ölçüde azaltılabilir. Kubecost ile GPU maliyetini takip etmeyi unutmayın.

---

## 🎉 Tebrikler!

Bu noktaya kadar geldiyseniz, 12 kapsamlı kategoride Kubernetes 2026'nın tüm kritik konularını tamamladınız:

- **Temel → Kurulum → Ağ → GitOps → Güvenlik**

Bu dokümantasyon, 2026 standartlarında production-ready bir Kubernetes cluster kurmanız ve yönetmeniz için gereken tüm teorik ve pratik bilgiyi içermektedir.

