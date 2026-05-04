# Kubeflow Pipelines

Kubeflow, Kubernetes üzerinde makine öğrenmesi iş akışlarını çalıştırmak için tasarlanmış açık kaynak platformdur. ML Pipelines bileşeni, veri hazırlama → model eğitimi → değerlendirme → deployment adımlarını otomatize eder.

---

## Mimari

```
[Kubeflow Dashboard]
   │
   ├── Pipelines    → ML iş akışı tanımı ve çalıştırma
   ├── Notebooks    → JupyterLab (GPU destekli)
   ├── Katib        → Hyperparameter tuning
   ├── KFServing    → Model serving (KServe)
   └── Training Op  → PyTorch/TensorFlow dağıtık eğitim
```

---

## Kurulum

```bash
# Kubeflow 1.8+ kurulumu (kustomize ile)
git clone https://github.com/kubeflow/manifests.git
cd manifests

# Tüm bileşenler
while ! kustomize build example | kubectl apply -f -; do
  echo "Yeniden deneniyor..."; sleep 10
done

# Sadece Pipelines
kustomize build apps/pipeline/upstream/env/platform-agnostic-multi-user | \
  kubectl apply -f -

# Dashboard erişimi
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
```

---

## Pipeline Tanımı (KFP SDK v2)

```python
# pip install kfp==2.7.0
from kfp import dsl
from kfp.dsl import Dataset, Input, Output, Model, Metrics

# Komponent 1: Veri Hazırlama
@dsl.component(
    base_image="python:3.11",
    packages_to_install=["pandas==2.1.0", "scikit-learn==1.3.0"]
)
def prepare_data(
    raw_data_path: str,
    output_dataset: Output[Dataset],
    test_size: float = 0.2
):
    import pandas as pd
    from sklearn.model_selection import train_test_split
    import json

    df = pd.read_csv(raw_data_path)
    train_df, test_df = train_test_split(df, test_size=test_size, random_state=42)

    with open(output_dataset.path, 'w') as f:
        json.dump({
            'train': train_df.to_dict(),
            'test': test_df.to_dict()
        }, f)


# Komponent 2: Model Eğitimi
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

    with open(dataset.path) as f:
        data = json.load(f)

    train_df = pd.DataFrame(data['train'])
    test_df  = pd.DataFrame(data['test'])

    X_train = train_df.drop('label', axis=1)
    y_train = train_df['label']
    X_test  = test_df.drop('label', axis=1)
    y_test  = test_df['label']

    model = RandomForestClassifier(n_estimators=n_estimators, random_state=42)
    model.fit(X_train, y_train)

    accuracy = accuracy_score(y_test, model.predict(X_test))

    # Metrik kaydet
    metrics_output.log_metric("accuracy", accuracy)
    metrics_output.log_metric("n_estimators", n_estimators)

    # Modeli kaydet
    joblib.dump(model, model_output.path)
    print(f"Model accuracy: {accuracy:.4f}")


# Komponent 3: Model Deployment
@dsl.component(
    base_image="bitnami/kubectl:latest"
)
def deploy_model(
    model: Input[Model],
    model_name: str,
    namespace: str = "production"
):
    import subprocess
    # KServe InferenceService oluştur
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
    subprocess.run(['kubectl', 'apply', '-f', '/tmp/isvc.yaml'], check=True)


# Pipeline Tanımı
@dsl.pipeline(
    name="classification-pipeline",
    description="Veri hazırlama → Eğitim → Deploy"
)
def ml_pipeline(
    data_path: str = "gs://my-bucket/data/train.csv",
    model_name: str = "rf-classifier",
    n_estimators: int = 100
):
    # Adım 1: Veri hazırla
    data_step = prepare_data(
        raw_data_path=data_path
    )

    # Adım 2: Model eğit (GPU node'da çalıştır)
    train_step = train_model(
        dataset=data_step.outputs["output_dataset"],
        n_estimators=n_estimators
    ).set_accelerator_type("NVIDIA_TESLA_T4") \
     .set_accelerator_limit(1) \
     .set_memory_limit("8G") \
     .set_cpu_limit("4")

    # Koşullu deploy: accuracy > 0.85 ise deploy et
    with dsl.If(train_step.outputs["metrics_output"] > 0.85):
        deploy_model(
            model=train_step.outputs["model_output"],
            model_name=model_name
        )


# Pipeline'ı derle ve yükle
from kfp import compiler
compiler.Compiler().compile(ml_pipeline, 'pipeline.yaml')
```

---

## Pipeline Çalıştırma

```python
import kfp

client = kfp.Client(host="http://localhost:8080")

# Pipeline yükle
pipeline = client.upload_pipeline(
    pipeline_package_path='pipeline.yaml',
    pipeline_name='Classification Pipeline v1.0'
)

# Çalıştır
run = client.create_run_from_pipeline_func(
    ml_pipeline,
    arguments={
        'data_path': 'gs://company-ml/data/customer_data.csv',
        'model_name': 'customer-classifier',
        'n_estimators': 200
    },
    run_name='Production Run 2026-04-25',
    experiment_name='Customer Classification'
)

print(f"Run URL: {client.run_url(run.run_id)}")
```

---

## Katib — Hyperparameter Tuning

```yaml
apiVersion: kubeflow.org/v1beta1
kind: Experiment
metadata:
  name: rf-hyperparameter-tuning
  namespace: kubeflow
spec:
  objective:
    type: maximize
    goal: 0.95
    objectiveMetricName: accuracy

  algorithm:
    algorithmName: bayesianoptimization    # Bayesian, Random, Grid

  parallelTrialCount: 3
  maxTrialCount: 20
  maxFailedTrialCount: 3

  parameters:
  - name: n_estimators
    parameterType: int
    feasibleSpace:
      min: "50"
      max: "500"
  - name: max_depth
    parameterType: int
    feasibleSpace:
      min: "3"
      max: "20"
  - name: learning_rate
    parameterType: double
    feasibleSpace:
      min: "0.001"
      max: "0.1"

  trialTemplate:
    primaryContainerName: training
    trialParameters:
    - name: n_estimators
      reference: n_estimators
    trialSpec:
      apiVersion: batch/v1
      kind: Job
      spec:
        template:
          spec:
            containers:
            - name: training
              image: ghcr.io/company/ml-trainer:1.0.0
              command:
              - python
              - train.py
              - --n_estimators=${trialParameters.n_estimators}
              - --max_depth=${trialParameters.max_depth}
```

---

## KServe — Model Serving

```yaml
# Eğitilmiş modeli servis et
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: customer-classifier
  namespace: production
spec:
  predictor:
    sklearn:
      storageUri: gs://company-ml/models/customer-classifier/v3
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
  transformer:
    containers:
    - name: preprocess
      image: ghcr.io/company/feature-transformer:v1.2
```

```bash
# Model'e istek gönder
curl -X POST http://customer-classifier.production.svc.cluster.local/v1/models/customer-classifier:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[1.2, 3.4, 5.6, 7.8]]}'
```

> [!TIP]
> Kubeflow pipeline'larını ArgoCD ile GitOps'a entegre edin — `pipeline.yaml` dosyasını Git'te saklayın, her değişiklikte otomatik çalıştırın.
