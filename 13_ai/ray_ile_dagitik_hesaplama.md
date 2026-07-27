# Ray ile Dağıtık Yapay Zeka Hesaplamaları

Yapay zeka modellerinin ve verilerin boyutu tek bir sunucunun sınırlarını aştığında, hesaplama yükünü birden fazla makineye dağıtmak gerekir. **Ray**, Python uygulamalarını ve makine öğrenimi iş yüklerini (model eğitimi, hyperparameter tuning, model serving vb.) sıfır kod değişikliğine yakın bir çabayla binlerce çekirdek ve GPU üzerinde dağıtık olarak çalıştırmayı sağlayan açık kaynaklı bir kütüphanedir.

Kubernetes üzerinde Ray çalıştırmak için **KubeRay** operatör yapısı kullanılır.

---

## 1. Karşılaştırma: K8s Üzerindeki Dağıtık Araçlar

| Araç | Güçlü Olduğu Alan | K8s Entegrasyonu |
|:-----|:-----------------|:-----------------|
| **Kubeflow** | ML iş akışı orkestrasyonu (Pipeline) | Kubernetes Yerel (CRD) |
| **Spark** | Yapılandırılmış büyük veri (Big Data) işleme | Spark Operator / YARN |
| **Ray (KubeRay)** | Dağıtık model eğitimi, LLM inference, Reinforcement Learning | KubeRay Operator |

---

## 2. KubeRay Operatör Kurulumu (Helm)

Kubernetes kümenizin Ray kümelerini (RayCluster) yönetebilmesi için öncelikle KubeRay Operatörünü kurmalıyız:

```bash
# Helm reposunu ekleyin
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

# Operatörü yükleyin
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay \
  --create-namespace \
  --version 1.1.0
```

---

## 3. RayCluster Yapısı

KubeRay, bir ana düğüm (**Head Node**) ve işçi düğümlerinden (**Worker Nodes**) oluşan dinamik bir RayCluster kaynağı sunar.

Örnek bir `RayCluster` YAML dosyası:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ray_ile_dagitik_hesaplama_manifest_1.yaml](../Manifests/12_ai/ray_ile_dagitik_hesaplama_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Dağıtık Model Eğitimi (Ray Train)

Ray Train, PyTorch ve TensorFlow gibi popüler kütüphaneleri dağıtık çalıştırmak için wrapper sağlar.

Aşağıdaki Python kodu, Ray kullanarak 8 adet GPU işçisi (worker) üzerinde dağıtık PyTorch modeli eğitir:

```python
# train.py — Ray ile dağıtık PyTorch eğitimi
import ray
from ray.train.torch import TorchTrainer
from ray.train import ScalingConfig, RunConfig, CheckpointConfig

# Model eğitim fonksiyonu (Her işçi bu fonksiyonu çalıştırır)
def train_func(config):
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader
    from ray.train.torch import prepare_model, prepare_data_loader

    # 1. Klasik PyTorch Modeli Tanımla
    model = nn.Sequential(
        nn.Linear(768, 512),
        nn.ReLU(),
        nn.Linear(512, 10)
    )
    # Ray ile modeli dağıtık (DDP) modele çevir
    model = prepare_model(model)

    optimizer = torch.optim.Adam(model.parameters(), lr=config["lr"])
    criterion = nn.CrossEntropyLoss()

    # 2. Dağıtık Veri Setini Yükle
    dataset = ray.data.read_parquet("s3://company-ml-bucket/train-data/")
    train_loader = prepare_data_loader(
        DataLoader(dataset.to_torch(batch_size=config["batch_size"]))
    )

    # 3. Eğitim Döngüsü
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

        # Metrikleri raporla ve checkpoint kaydet
        ray.train.report({"loss": total_loss / len(train_loader), "epoch": epoch})

# Ray Dağıtık Eğitim Yapılandırması
trainer = TorchTrainer(
    train_func,
    train_loop_config={
        "lr": 1e-4,
        "batch_size": 64,
        "epochs": 5
    },
    scaling_config=ScalingConfig(
        num_workers=8,               # 8 adet paralel işçi çalışacak
        use_gpu=True,                # GPU kullanımı aktif
        resources_per_worker={"GPU": 1, "CPU": 8, "memory": 32 * 1024**3}
    ),
    run_config=RunConfig(
        name="dist-llm-training",
        storage_path="s3://company-ml-bucket/ray-checkpoints/",
        checkpoint_config=CheckpointConfig(
            num_to_keep=2,
            checkpoint_score_attribute="loss",
            checkpoint_score_order="min"
        )
    )
)

# Eğitimi başlat
result = trainer.fit()
print(f"Eğitim Tamamlandı! En iyi checkpoint: {result.best_checkpoints[0]}")
```

---

## 5. Ray Serve ile Model Sunumu (Inference)

**Ray Serve**, özellikle LLM ve çoklu model boru hatlarını (Pipeline) çalıştırmak amacıyla tasarlanmış, Ray tabanlı bir model sunum kütüphanesidir.

```python
# llm_serve.py — Ray Serve ile LLM Sunumu
import ray
from ray import serve
from transformers import pipeline
import torch

@serve.deployment(
    num_replicas=2, # Başlangıçta 2 kopya çalışır
    ray_actor_options={"num_gpus": 1, "num_cpus": 4},
    autoscaling_config={
        "min_replicas": 1,
        "max_replicas": 8,
        "target_num_ongoing_requests_per_replica": 10
    }
)
class LLMDeployment:
    def __init__(self):
        # Llama modelini HuggingFace üzerinden yükle
        self.model = pipeline(
            "text-generation",
            model="meta-llama/Llama-2-7b-chat-hf",
            torch_dtype=torch.float16,
            device_map="auto"
        )

    async def __call__(self, request):
        data = await request.json()
        prompt = data["prompt"]

        output = self.model(prompt, max_new_tokens=256)
        return {"response": output[0]["generated_text"]}

# Ray Serve uygulamasını bağlayıp başlatın
serve.run(LLMDeployment.bind(), route_prefix="/llm")
```

---

## 6. Kubernetes Üzerinde İzleme ve Takip

Ray kümenizin durumunu izlemek ve eğitim süreçlerini takip etmek için aşağıdaki CLI yöntemlerini kullanabilirsiniz:

```bash
# 1. Ray Dashboard arayüzüne port-forward ile bağlanın (Grafikler ve CPU/GPU takibi)
kubectl port-forward svc/ray-cluster-production-head-svc -n ray-system 8265:8265

# 2. Çalışan Ray işlerini (Jobs) listeleme
kubectl get rayjob -n ray-system

# 3. Ray Cluster durumunu sorgulama
kubectl get raycluster -n ray-system
```

---

## 7. Özet

Ray, Python geliştiricileri için altyapı karmaşasını gizleyerek dağıtık yapay zeka işlemlerini standartlaştırır. KubeRay sayesinde ise bu Ray kümeleri Kubernetes üzerinde tamamen otonom olarak yönetilebilir, ölçeklenebilir ve izlenebilir.

Yapay zeka mimarilerinin ardından, bir sonraki ve son alt başlığımızda; konteynerlerden kat kat daha hafif, cold-start süresi milisaniyelerin altında olan yeni nesil **WebAssembly (WASM)** iş yüklerinin Kubernetes üzerinde nasıl çalıştırılacağını inceleyeceğiz.
