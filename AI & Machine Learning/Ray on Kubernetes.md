# Ray on Kubernetes

Ray, dağıtık Python uygulamaları ve büyük ölçekli ML iş yükleri için tasarlanmış framework'tür. Kubernetes üzerinde Ray Cluster ile dağıtık model eğitimi, inference ve data processing kolaylaşır.

---

## Neden Ray?

| Araç | Güçlü Olduğu Alan |
|:-----|:-----------------|
| **Kubeflow** | ML pipeline orchestration |
| **Ray** | Dağıtık hesaplama, aktif/önden yükleme, reinforcement learning |
| **Spark** | Büyük veri batch processing |
| **Ray + KubeRay** | LLM inference, distributed training, parallel hyperparameter search |

---

## KubeRay Kurulumu

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay \
  --create-namespace \
  --version 1.1.0
```

---

## RayCluster

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: ml-cluster
  namespace: ray-system
spec:
  rayVersion: "2.10.0"

  # Head node (cluster yöneticisi)
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
      num-cpus: "0"          # Head node hesaplama yapmasın
    template:
      spec:
        containers:
        - name: ray-head
          image: rayproject/ray-ml:2.10.0-gpu
          resources:
            requests:
              cpu: "2"
              memory: "8Gi"
            limits:
              cpu: "4"
              memory: "16Gi"

  # Worker node'lar
  workerGroupSpecs:
  - groupName: gpu-workers
    replicas: 4
    minReplicas: 1
    maxReplicas: 8         # Autoscaling
    rayStartParams:
      num-gpus: "1"
    template:
      spec:
        containers:
        - name: ray-worker
          image: rayproject/ray-ml:2.10.0-gpu
          resources:
            requests:
              cpu: "8"
              memory: "32Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "16"
              memory: "64Gi"
              nvidia.com/gpu: "1"
        nodeSelector:
          cloud.google.com/gke-accelerator: nvidia-tesla-a100
```

---

## RayJob — Tek Seferlik İş

```yaml
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: train-llm
  namespace: ray-system
spec:
  entrypoint: "python /app/train.py --model llama2-7b --epochs 3"

  runtimeEnvYAML: |
    pip:
      - torch==2.1.0
      - transformers==4.36.0
      - datasets==2.16.0
    env_vars:
      HF_TOKEN: "hf_your_token"

  shutdownAfterJobFinishes: true    # İş bitince cluster'ı sil
  ttlSecondsAfterFinished: 3600

  rayClusterSpec:
    rayVersion: "2.10.0"
    headGroupSpec:
      rayStartParams: {}
      template:
        spec:
          containers:
          - name: ray-head
            image: rayproject/ray-ml:2.10.0-gpu
            resources:
              limits:
                cpu: "4"
                memory: "16Gi"

    workerGroupSpecs:
    - groupName: gpu-workers
      replicas: 8
      template:
        spec:
          containers:
          - name: ray-worker
            image: rayproject/ray-ml:2.10.0-gpu
            resources:
              limits:
                cpu: "16"
                memory: "64Gi"
                nvidia.com/gpu: "8"    # 8x GPU per worker
```

---

## Dağıtık Eğitim Kodu

```python
# train.py — Ray ile dağıtık PyTorch eğitimi
import ray
from ray.train.torch import TorchTrainer
from ray.train import ScalingConfig, RunConfig, CheckpointConfig

def train_func(config):
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader
    from ray.train.torch import prepare_model, prepare_data_loader

    # Model
    model = nn.Sequential(
        nn.Linear(768, 512),
        nn.ReLU(),
        nn.Linear(512, 10)
    )
    model = prepare_model(model)    # Dağıtık modele çevir

    optimizer = torch.optim.Adam(model.parameters(), lr=config["lr"])
    criterion = nn.CrossEntropyLoss()

    # Dataset
    dataset = ray.data.read_parquet("s3://company-ml/train-data/")
    train_loader = prepare_data_loader(
        DataLoader(dataset.to_torch(batch_size=config["batch_size"]))
    )

    for epoch in range(config["epochs"]):
        model.train()
        total_loss = 0.0
        for batch in train_loader:
            X, y = batch["features"], batch["label"]
            optimizer.zero_grad()
            output = model(X)
            loss = criterion(output, y)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

        # Epoch metriği raporla
        ray.train.report({"loss": total_loss / len(train_loader), "epoch": epoch})


# RayJob'dan çalıştır
trainer = TorchTrainer(
    train_func,
    train_loop_config={
        "lr": 1e-4,
        "batch_size": 64,
        "epochs": 10
    },
    scaling_config=ScalingConfig(
        num_workers=8,              # 8 worker
        use_gpu=True,               # Her worker'da GPU
        resources_per_worker={"GPU": 1, "CPU": 8, "memory": 32 * 1024**3}
    ),
    run_config=RunConfig(
        name="llm-training-run",
        storage_path="s3://company-ml/ray-results/",
        checkpoint_config=CheckpointConfig(
            num_to_keep=3,
            checkpoint_score_attribute="loss",
            checkpoint_score_order="min"
        )
    )
)

result = trainer.fit()
print(f"Best checkpoint: {result.best_checkpoints[0]}")
```

---

## Ray Serve — LLM Inference

```python
# llm_serve.py — Kubernetes üzerinde LLM serving
import ray
from ray import serve
from transformers import pipeline
import torch

@serve.deployment(
    num_replicas=2,
    ray_actor_options={
        "num_gpus": 1,
        "num_cpus": 4,
        "memory": 32 * 1024**3
    },
    autoscaling_config={
        "min_replicas": 1,
        "max_replicas": 8,
        "target_num_ongoing_requests_per_replica": 5
    }
)
class LLMDeployment:
    def __init__(self):
        self.model = pipeline(
            "text-generation",
            model="meta-llama/Llama-2-7b-chat-hf",
            torch_dtype=torch.float16,
            device_map="auto"
        )

    async def __call__(self, request):
        data = await request.json()
        prompt = data["prompt"]
        max_tokens = data.get("max_tokens", 512)

        output = self.model(
            prompt,
            max_new_tokens=max_tokens,
            temperature=0.7,
            do_sample=True
        )
        return {"response": output[0]["generated_text"]}


# Deploy et
serve.run(LLMDeployment.bind(), route_prefix="/llm")
```

---

## RayService — Kalıcı Servis

```yaml
apiVersion: ray.io/v1
kind: RayService
metadata:
  name: llm-service
  namespace: ray-system
spec:
  serviceUnhealthySecondThreshold: 300
  deploymentUnhealthySecondThreshold: 300

  serveConfigV2: |
    applications:
    - name: llm-app
      import_path: llm_serve:LLMDeployment
      runtime_env:
        pip:
        - transformers==4.36.0
        - torch==2.1.0
        env_vars:
          HF_TOKEN: "hf_your_token"

  rayClusterConfig:
    rayVersion: "2.10.0"
    headGroupSpec:
      rayStartParams:
        dashboard-host: "0.0.0.0"
      template:
        spec:
          containers:
          - name: ray-head
            image: rayproject/ray-ml:2.10.0-gpu
            resources:
              limits:
                cpu: "4"
                memory: "16Gi"
    workerGroupSpecs:
    - groupName: gpu-workers
      replicas: 2
      minReplicas: 1
      maxReplicas: 4
      template:
        spec:
          containers:
          - name: ray-worker
            image: rayproject/ray-ml:2.10.0-gpu
            resources:
              limits:
                cpu: "16"
                memory: "64Gi"
                nvidia.com/gpu: "1"
```

---

## İzleme

```bash
# Ray Dashboard
kubectl port-forward svc/ml-cluster-head-svc -n ray-system 8265:8265

# Job durumu
kubectl get rayjob -n ray-system
kubectl describe rayjob train-llm -n ray-system

# Cluster durumu
kubectl get raycluster -n ray-system

# Serve durumu
ray status --address http://localhost:8265
```

> [!TIP]
> Büyük modeller (70B+) için `tensor_parallel_size` ve `pipeline_parallel_size` ayarlarını yapın. Ray Serve + vLLM kombinasyonu, production LLM inference için 2026 standardıdır.
