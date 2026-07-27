# KServe ile Yapay Zeka Model Sunumu (Inference)

Modeli eğitmek işin başlangıcıdır; ancak bu modeli üretim (production) ortamında düşük gecikme süresiyle (latency), yüksek throughput ile ve dinamik ölçeklenebilir şekilde dış dünyaya sunmak (inference serving) bambaşka bir mühendislik problemidir.

**KServe**, Kubernetes üzerinde bulut-yerel (cloud-native) standartlarında, çoklu framework destekli yapay zeka model sunum altyapısı sağlar.

---

## 1. Neden KServe?

Geleneksel yöntemlerle bir modeli API haline getirmek ile KServe kullanmak arasındaki mimari fark şu şekildedir:

```
Geleneksel:  Model Dosyası ──► Flask/FastAPI ──► Docker ──► Kubernetes Deployment (Manuel ölçekleme, GPU israfı)
KServe:      Model Dosyası ──► KServe InferenceService YAML ──► (Otomatik vLLM/Triton, 0'a ölçeklenme, Canary, Metrikler)
```

**KServe Avantajları (2026 Standartları):**

- **Çoklu Motor Desteği:** HuggingFace, vLLM, PyTorch, TensorFlow, Triton, ONNX, Sklearn ve XGBoost modellerini doğrudan tanır.
- **Canary Dağıtımları:** Trafiği iki model versiyonu arasında (Örn: %90 v1, %10 v2) akıllıca dağıtır.
- **Serverless Ölçeklendirme:** İstek gelmediğinde pod sayısını 0'a (sıfıra) indirerek pahalı GPU maliyetlerini sıfırlar. İstek geldiğinde otomatik uyanır (cold-start optimizasyonu).

---

## 2. KServe Kurulumu (Helm — v0.14+)

Modern Kubernetes kümelerinde KServe kurulumu Helm aracılığıyla gerçekleştirilir. Kurulum için öncelikle bir sertifika yöneticisi (`cert-manager`) kurulu olmalıdır.

```bash
# 1. Cert-Manager Kurulumu
helm install cert-manager \
  oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true

# 2. KServe Helm Kurulumu
helm repo add kserve https://kserve.github.io/helm-charts
helm repo update

# RawDeployment Modu (Knative / Serverless katmanı gerektirmeyen, doğrudan çalışan mod)
helm install kserve kserve/kserve \
  --namespace kserve \
  --create-namespace \
  --version 0.14.0 \
  --set kserve.controller.deploymentMode=RawDeployment
```

---

## 3. Pratik Uygulamalar (InferenceService Örnekleri)

### Örnek 1: HuggingFace Metin Sınıflandırma Modeli

HuggingFace üzerindeki hazır bir modeli doğrudan çekip API haline getirmek için aşağıdaki YAML kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kserve_ve_model_sunumu_manifest_1.yaml](../Manifests/12_ai/kserve_ve_model_sunumu_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Örnek 2: vLLM ile Büyük Dil Modeli (LLM) Sunumu

2026 yılının LLM sunumu için endüstri standardı **vLLM** motorudur. Llama-3 modelini çalıştırmak için yazılan örnek `InferenceService`:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kserve_ve_model_sunumu_manifest_2.yaml](../Manifests/12_ai/kserve_ve_model_sunumu_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Örnek 3: S3 Depolama Alanından Özel Model Yükleme (Sklearn)

Eğittiğiniz ve AWS S3 üzerine kaydettiğiniz bir model dosyasını sunmak için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kserve_ve_model_sunumu_manifest_3.yaml](../Manifests/12_ai/kserve_ve_model_sunumu_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. API Üzerinden Sorgulama (vLLM / Llama-3)

Servis ayağa kalktıktan sonra, OpenAI uyumlu API formatında doğrudan sorgulama yapabilirsiniz:

```bash
curl http://llama-3-serving.ml-serving.svc.cluster.local/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Meta-Llama-3-8B-Instruct",
    "messages": [
      {"role": "user", "content": "Kubernetes nedir ve neden önemlidir?"}
    ],
    "temperature": 0.7
  }'
```

---

## 5. Canary Dağıtımları (A/B Testi)

Mevcut çalışan bir modelin yeni versiyonunu (v2) test etmek amacıyla trafiğin sadece %10'unu yeni modele yönlendirmek için `canaryTrafficPercent` tanımı kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kserve_ve_model_sunumu_manifest_4.yaml](../Manifests/12_ai/kserve_ve_model_sunumu_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Serverless Mod: 0'a (Sıfıra) Ölçeklenme

KServe Serverless modda (Knative kurulu olduğunda) çalışırken, podların 0'a inmesi için Ingress annotation'ları kullanılır:

```yaml
metadata:
  annotations:
    autoscaling.knative.dev/min-scale: "0" # İstek olmadığında podları tamamen kapat (0 GPU tüketimi)
    autoscaling.knative.dev/max-scale: "5" # Yoğunluk anında maksimum 5 pod'a kadar ölçekle
```

---

## 7. Model İzleme Metrikleri (Prometheus)

KServe, modellerin performansını izlemek için yerleşik metrikler üretir. Prometheus dashboard'larında kullanabileceğiniz kritik sorgular:

```promql
# Model İstek Hızı (Trafik throughput - req/sec)
rate(revision_request_count_total{namespace_name="ml-serving"}[5m])

# Model Hata Oranı (5xx alan isteklerin oranı)
rate(revision_request_count_total{namespace_name="ml-serving", response_code_class="5xx"}[5m])

# P99 Latency (Gecikme süresi - Saniye cinsinden)
histogram_quantile(0.99, rate(revision_request_latencies_bucket{namespace_name="ml-serving"}[5m])) / 1000
```

---

## 8. Özet

KServe, karmaşık yapay zeka modellerini üretim ortamına taşımayı ve yönetmeyi standartlaştırır. Modellerinizi dış dünyaya sunduğunuza göre, bir sonraki aşama bu modellerin üretim süreçlerini (data preparation, training, validation) uçtan uca otomatize edecek olan **Kubeflow Pipelines** sistemini kurmaktır.
