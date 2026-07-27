# Kubeflow Pipelines ile MLOps Süreçleri

Yapay zeka projelerinde en büyük zorluklardan biri, veri hazırlama (data preparation), model eğitimi (training), değerlendirme (evaluation) ve canlıya alma (deployment) adımlarının manuel yapılmasıdır. Bu adımlar otomatize edilmediğinde modeller güncelliğini yitirir ve kod ile model sürümleri arasındaki bağ kopar.

**Kubeflow**, Kubernetes üzerinde makine öğrenimi (ML) iş akışlarını çalıştırmak ve otomatize etmek amacıyla geliştirilmiş en popüler açık kaynaklı MLOps platformudur. **Kubeflow Pipelines (KFP)** ise bu platformun iş akışlarını (workflow) yöneten ana bileşenidir.

---

## 1. Kubeflow Mimarisi ve Bileşenleri

Kubeflow, yapay zeka ekiplerinin ihtiyaç duyduğu tüm araçları tek bir merkezi arayüz (dashboard) altında birleştirir:

```
[ Kubeflow Merkezi Dashboard ]
  ├── Notebooks   ──► JupyterLab, RStudio (GPU destekli yerel geliştirme)
  ├── Pipelines   ──► ML iş akışlarının tasarımı, zamanlanması ve izlenmesi
  ├── Katib       ──► Otomatik hiperparametre optimizasyonu (Hyperparameter Tuning)
  └── Training Op ──► PyTorch/TensorFlow modellerinin birden fazla node üzerinde dağıtık eğitilmesi
```

---

## 2. Kubeflow Kurulumu (Kustomize ile)

Kubeflow Pipelines, hafif ve bağımsız bir şekilde Kubernetes kümesine kurulabilir. Kurulum için **Kustomize** aracı kullanılır:

```bash
# 1. Kubeflow manifestosunu klonlayın
git clone https://github.com/kubeflow/manifests.git
cd manifests

# 2. Sadece Pipelines bileşenini kurun (Çoklu kullanıcı desteği ile)
kustomize build apps/pipeline/upstream/env/platform-agnostic-multi-user | kubectl apply -f -

# 3. Kubeflow Dashboard arayüzüne port-forward ile bağlanın
kubectl port-forward svc/ml-pipeline-ui -n kubeflow 8080:80
```

*Arayüze erişmek için tarayıcınızdan `http://localhost:8080` adresini açabilirsiniz.*

---

## 3. Pipeline Tanımlama (KFP SDK v2)

Kubeflow Pipelines üzerinde bir iş akışı oluşturmak için Python dili kullanılır. İş akışındaki her adım (komponent) izole birer konteyner olarak çalışır.

Aşağıdaki Python kodu, baştan sona bir ML boru hattını (Pipeline) tanımlar:

```python
# Gerekli kütüphane: pip install kfp==2.7.0
from kfp import dsl
from kfp.dsl import Dataset, Input, Output, Model, Metrics

# Adım 1: Veri Hazırlama Komponenti
@dsl.component(
    base_image="python:3.11",
    packages_to_install=["pandas==2.1.0", "scikit-learn==1.3.0"]
)
def prepare_data(
    raw_data_path: str,
    output_dataset: Output[Dataset]
):
    import pandas as pd
    from sklearn.model_selection import train_test_split
    import json

    # Veriyi indir ve temizle
    df = pd.read_csv(raw_data_path)
    train_df, test_df = train_test_split(df, test_size=0.2, random_state=42)

    # Hazırlanan veriyi sonraki adımın okuyabilmesi için kaydet
    with open(output_dataset.path, 'w') as f:
        json.dump({
            'train': train_df.to_dict(),
            'test': test_df.to_dict()
        }, f)

# Adım 2: Model Eğitimi Komponenti (GPU Desteği ile)
@dsl.component(
    base_image="python:3.11",
    packages_to_install=["scikit-learn==1.3.0", "joblib"]
)
def train_model(
    dataset: Input[Dataset],
    model_output: Output[Model],
    metrics_output: Output[Metrics],
    n_estimators: int = 100
):
    import json
    import joblib
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score
    import pandas as pd

    # Bir önceki adımdan gelen veriyi oku
    with open(dataset.path) as f:
        data = json.load(f)

    train_df = pd.DataFrame(data['train'])
    test_df  = pd.DataFrame(data['test'])

    X_train = train_df.drop('label', axis=1)
    y_train = train_df['label']
    X_test  = test_df.drop('label', axis=1)
    y_test  = test_df['label']

    # Modeli eğit
    model = RandomForestClassifier(n_estimators=n_estimators, random_state=42)
    model.fit(X_train, y_train)

    # Doğruluk (accuracy) hesapla ve metrik olarak kaydet
    accuracy = accuracy_score(y_test, model.predict(X_test))
    metrics_output.log_metric("accuracy", accuracy)

    # Modeli kaydet
    joblib.dump(model, model_output.path)

# Adım 3: KServe ile Otomatik Canlıya Alma (Deploy) Komponenti
@dsl.component(
    base_image="bitnami/kubectl:latest"
)
def deploy_model(
    model: Input[Model],
    model_name: str,
    namespace: str = "production"
):
    import subprocess
    # KServe InferenceService YAML manifestosu üret
    manifest = f"""
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: {model_name}
  namespace: {namespace}
spec:
  predictor:
    sklearn:
      storageUri: {model.uri}
"""
    with open('/tmp/isvc.yaml', 'w') as f:
        f.write(manifest)

    # Kümede uygula
    subprocess.run(['kubectl', 'apply', '-f', '/tmp/isvc.yaml'], check=True)

# Pipeline (İş Akışı) Yapısının Kurulması
@dsl.pipeline(
    name="mlops-end-to-end-pipeline",
    description="Veri Hazırlama -> GPU ile Eğitim -> KServe ile Canlıya Alma"
)
def ml_pipeline(
    data_path: str = "https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv",
    model_name: str = "titanic-model"
):
    # 1. Adım: Veri Hazırlama
    prep_task = prepare_data(raw_data_path=data_path)

    # 2. Adım: Model Eğitimi (GPU tahsisi ve limit sınırları belirleniyor)
    train_task = train_model(
        dataset=prep_task.outputs["output_dataset"],
        n_estimators=150
    )
    train_task.set_cpu_limit("2")
    train_task.set_memory_limit("4G")
    train_task.set_accelerator_limit(1)
    train_task.set_accelerator_type("NVIDIA_TESLA_T4") # Düğümdeki GPU türü

    # 3. Adım: Koşullu Canlıya Alma (Eğer doğruluk/accuracy > 0.80 ise)
    with dsl.If(train_task.outputs["metrics_output"].outputs["accuracy"] > 0.80):
        deploy_task = deploy_model(
            model=train_task.outputs["model_output"],
            model_name=model_name
        )

# Pipeline Derleme
from kfp import compiler
compiler.Compiler().compile(ml_pipeline, 'ml_pipeline.yaml')
```

---

## 4. Pipeline'ı Kod Üzerinden Çalıştırma (KFP Client)

Derlenen `ml_pipeline.yaml` dosyasını Kubeflow sunucusuna yüklemek ve bir iş akışı başlatmak için Python SDK'sını kullanabiliriz:

```python
import kfp

# Kubeflow Pipelines API adresine bağlanın
client = kfp.Client(host="http://localhost:8080")

# İş akışını gönderin ve çalıştırın
run = client.create_run_from_pipeline_func(
    ml_pipeline,
    arguments={
        'data_path': 'https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv',
        'model_name': 'titanic-classifier'
    },
    run_name='Titanic Run v1.0',
    experiment_name='Titanic Experiment'
)

print(f"İş Akışı Başlatıldı! Arayüz linki: {client.run_url(run.run_id)}")
```

---

## 5. Katib ile Otomatik Parametre Seçimi (Hyperparameter Tuning)

Modelleri eğitirken hangi parametrelerin (Örn: Random Forest için kaç ağaç kullanılmalı?) en iyi sonucu vereceğini tahmin etmek zordur. **Katib**, farklı kombinasyonları Kubernetes üzerinde paralel podlar halinde çalıştırarak en iyi sonucu veren parametreyi bulur.

Aşağıdaki Katib YAML dosyası, en yüksek doğruluk (`accuracy`) oranına sahip parametreleri bulmak için paralel 3 deneme (Trial) çalıştırır:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kubeflow_ve_veri_akislari_manifest_1.yaml](../Manifests/12_ai/kubeflow_ve_veri_akislari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Özet

Kubeflow Pipelines, makine öğrenimi süreçlerini standart hale getirerek yazılım mühendisliği pratiklerini (CI/CD, GitOps) yapay zekaya entegre etmemizi sağlar. Bir sonraki bölümde, veri bilimi süreçlerinde büyük verileri paralel ve çok daha hızlı işleyebilmek için kullanılan **Ray** (KubeRay) altyapısını ele alacağız.
