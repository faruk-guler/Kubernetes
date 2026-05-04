# KServe & AI Inference Serving

Modeli eğitmek bir iştir; production'da servis etmek bambaşka bir mühendislik problemidir. KServe, Kubernetes üzerinde standart, ölçeklenebilir ve çoklu framework destekli model servis altyapısı sunar.

---

## Neden KServe?

```
Manuel:  Model → Flask → Docker → Deployment (ölçekleme yok, GPU boşta)
KServe:  InferenceService YAML → otomatik ölçekleme + GPU optimizasyonu
                                + A/B test + canary + Prometheus metrikleri
```

**2026 Desteklenen Framework'ler:** HuggingFace, vLLM, PyTorch, TensorFlow, Sklearn, XGBoost, ONNX, Triton Inference Server

---

## Kurulum (Helm — v0.14+)

> [!NOTE]
> KServe v0.13 ve öncesi `kubectl apply` raw manifest yöntemi kullanıyordu. v0.14'ten itibaren Helm standardı önerilir. Güncel sürüm: https://github.com/kserve/kserve/releases

```bash
# Cert-manager gerekli (henüz kurulu değilse)
helm install cert-manager \
  oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true

# KServe Helm kurulumu
helm repo add kserve https://kserve.github.io/helm-charts
helm repo update

# Güncel sürümü kontrol et
helm search repo kserve/kserve --versions | head -5

# Serverless mod (Knative gerektirir)
helm install kserve kserve/kserve \
  --namespace kserve \
  --create-namespace \
  --version 0.14.0

# RawDeployment mod (Knative gerektirmez — production önerisi)
helm install kserve kserve/kserve \
  --namespace kserve \
  --create-namespace \
  --version 0.14.0 \
  --set kserve.controller.deploymentMode=RawDeployment

# CRD'leri kontrol et
kubectl get crd | grep kserve
kubectl get pods -n kserve
```

---

## InferenceService Örnekleri

### HuggingFace Modeli

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: bert-sentiment
  namespace: ml-serving
spec:
  predictor:
    model:
      modelFormat:
        name: huggingface
      storageUri: "hf://distilbert-base-uncased-finetuned-sst-2-english"
      resources:
        requests:
          cpu: "1"
          memory: "4Gi"
        limits:
          cpu: "4"
          memory: "8Gi"
```

### vLLM ile LLM Serving (2026 Standardı)

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama-3-8b
  namespace: ml-serving
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      storageUri: "hf://meta-llama/Meta-Llama-3-8B-Instruct"
      args:
      - --max-model-len=8192
      - --tensor-parallel-size=1
      - --dtype=bfloat16
      resources:
        requests:
          cpu: "8"
          memory: "32Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "16"
          memory: "64Gi"
          nvidia.com/gpu: "1"
      env:
      - name: HUGGING_FACE_HUB_TOKEN
        valueFrom:
          secretKeyRef:
            name: hf-secret
            key: token
```

```bash
# OpenAI uyumlu API (vLLM)
curl -X POST http://llama-3-8b.ml-serving.svc/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "meta-llama/Meta-Llama-3-8B-Instruct", "prompt": "Kubernetes nedir?", "max_tokens": 200}'
```

### Sklearn / PyTorch (S3'ten Model)

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detector
  namespace: ml-serving
spec:
  predictor:
    sklearn:
      storageUri: "s3://company-models/fraud/v2"
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
```

---

## Canary Deployment (A/B Model Test)

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: recommendation
  namespace: ml-serving
spec:
  predictor:
    canaryTrafficPercent: 10    # v2 modeli → %10 trafik alır
    model:
      modelFormat:
        name: sklearn
      storageUri: "s3://company-models/rec/v1"    # v1 → %90
```

```bash
# Canary oranını artır (model başarılıysa)
kubectl patch inferenceservice recommendation -n ml-serving \
  --type merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent":50}}}'

# v2'yi production'a al
kubectl patch inferenceservice recommendation -n ml-serving \
  --type merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent":100}}}'
```

---

## Serverless — 0'a Ölçeklenme

```yaml
spec:
  predictor:
    minReplicas: 0      # Kullanılmıyorsa tamamen kapat
    maxReplicas: 10
    scaleMetric: rps    # Requests per second
    scaleTarget: 10     # RPS başına 1 replica
    model:
      modelFormat:
        name: sklearn
      storageUri: "s3://company-models/batch/v1"
```

---

## Model Storage URI Formatları

| Format | Örnek | Gereksinim |
|:-------|:------|:----------|
| **S3** | `s3://bucket/path` | AWS credentials veya IRSA |
| **GCS** | `gs://bucket/path` | GCP Service Account |
| **Azure Blob** | `https://account.blob.core.windows.net/container/path` | Azure credentials |
| **HuggingFace** | `hf://model-name` | `HUGGING_FACE_HUB_TOKEN` secret |
| **OCI** | `oci://ghcr.io/org/model:tag` | Registry credentials |
| **URI** | `https://...` | Public endpoint |

---

## İzleme ve Debug

```bash
# InferenceService durumu
kubectl get inferenceservices -n ml-serving
kubectl describe inferenceservice bert-sentiment -n ml-serving

# Logları gör
kubectl logs -l serving.kserve.io/inferenceservice=bert-sentiment \
  -n ml-serving -c kserve-container

# InferenceService URL
kubectl get inferenceservice bert-sentiment -n ml-serving \
  -o jsonpath='{.status.url}'
```

```promql
# Inference P99 latency (ms)
histogram_quantile(0.99,
  rate(revision_request_latencies_bucket{namespace_name="ml-serving"}[5m])
) / 1000

# GPU kullanım oranı
DCGM_FI_DEV_GPU_UTIL{namespace="ml-serving"}

# Inference throughput (req/s)
rate(revision_request_count_total{namespace_name="ml-serving"}[5m])

# Model serve hatası oranı
rate(revision_request_count_total{namespace_name="ml-serving",response_code_class="5xx"}[5m])
```

> [!TIP]
> LLM serving için vLLM backend, vanilla HuggingFace'e kıyasla throughput'u 5-10x artırır. PagedAttention algoritması sayesinde GPU belleği çok daha verimli kullanılır.
