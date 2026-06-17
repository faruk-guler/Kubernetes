# Admission Controllers ve Webhook'lar

## Admission Controller Nedir?

Kubernetes API Server'a bir istek geldiğinde (örneğin Pod oluşturma), bu istek kaydedilmeden önce iki kritik aşamadan geçer:

1. **Mutating Admission Control:** İsteği değiştirir (sidecar ekler, label ekler)
2. **Validating Admission Control:** İsteği kabul eder ya da reddeder

## Webhook Akışı

```
kubectl/ArgoCD → kube-apiserver → Mutating Webhook → Validating Webhook → etcd
                                       ↓                     ↓
                                  (değiştirir)           (onaylar/reddeder)
```

## ValidatingWebhookConfiguration

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: my-validation-webhook
webhooks:
- name: validate.mycompany.com
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["pods"]
  clientConfig:
    service:
      namespace: webhook-system
      name: webhook-service
      path: "/validate-pod"
    caBundle: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg==
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail              # Webhook'a ulaşılamazsa reddet
  timeoutSeconds: 10
```

## MutatingWebhookConfiguration

Otomatik sidecar ekleme örneği (Istio, Falco vb. bu yöntemi kullanır):

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: sidecar-injector
webhooks:
- name: inject.sidecar.mycompany.com
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE"]
    resources: ["pods"]
  clientConfig:
    service:
      namespace: sidecar-system
      name: sidecar-injector
      path: "/inject"
    caBundle: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg==
  admissionReviewVersions: ["v1"]
  sideEffects: None
  namespaceSelector:
    matchLabels:
      sidecar-injection: enabled   # Sadece bu label olan namespace'lerde çalış
```

## CEL ile ValidatingAdmissionPolicy (2026 Standardı — Webhook Gerektirmez)

2026'da basit doğrulamalar için harici webhook yazmaya (Go/Python kodu) gerek kalmadı. **ValidatingAdmissionPolicy** ile Common Expression Language (CEL) kullanarak YAML'da kural yazabilirsiniz:

```yaml
# 1. Policy Tanımı
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: min-replicas-policy
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: "object.spec.replicas >= 2"
    message: "Production deployment'larında en az 2 replika olmalıdır!"
  - expression: "object.spec.template.spec.containers.all(c, has(c.resources) && has(c.resources.limits))"
    message: "Tüm konteynerler limit tanımlamalıdır!"
---
# 2. Policy Bağlama
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: min-replicas-binding
spec:
  policyName: min-replicas-policy
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: production
```

> [!TIP]
> CEL politikaları, Go kodlu webhook'lardan çok daha hızlı çalışır çünkü ayrı bir pod gerektirmez. Basit kurallar için her zaman CEL tercih edin.

---

## Kyverno ve OPA Gatekeeper Webhook Entegrasyon Mekanizması

Kyverno ve OPA Gatekeeper gibi gelişmiş cloud-native politika yöneticileri (policy engines), cluster içindeki tüm işlemleri denetlemek için Kubernetes API Server'ın **Mutating/Validating Admission Webhook** mekanizmasını arka planda otomatik olarak kurar ve yönetir.

### 1. Webhook Kayıt (Registration) Mantığı
Bu araçları Helm ile yüklediğinizde, otomatik olarak cluster genelinde birer `MutatingWebhookConfiguration` ve `ValidatingWebhookConfiguration` nesnesi oluşturarak kendilerini API Server'a entegre ederler.

Örneğin, Kyverno kurulduğunda API Server'a kendisini şu şekilde bir webhook ile kaydeder:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: kyverno-resource-validating-webhook-cfg
webhooks:
- name: validate.kyverno.svc-fail
  rules:
  - apiGroups: ["*"]
    apiVersions: ["*"]
    operations: ["CREATE", "UPDATE", "DELETE", "CONNECT"]
    resources: ["*/*"]             # Cluster üzerindeki tüm kaynakları ve alt kaynakları izler
  clientConfig:
    service:
      namespace: kyverno
      name: kyverno-svc
      path: "/validate/fail"
    caBundle: <KYVERNO_CA_BUNDLE>   # TLS el sıkışması için otomatik oluşturulan CA
  failurePolicy: Fail              # Güvenlik önceliği: Kyverno çalışmıyorsa API isteklerini engelle
  sideEffects: None
  admissionReviewVersions: ["v1"]
```

### 2. failurePolicy: Fail ve Ignore Seçimi
Politika yöneticisi webhook tanımlarında `failurePolicy` alanı hayati bir rol oynar:
* **`failurePolicy: Fail` (Güvenli/Sıkı Mod):** Eğer Kyverno/OPA pod'u çökerse veya webhook sunucusu aşırı yükten yanıt veremezse, API Server **hiçbir yeni kaynağın oluşturulmasına veya güncellenmesine izin vermez** (istekler reddedilir). Production ortamlarında güvenlik açıklarını önlemek için bu mod tercih edilir.
* **`failurePolicy: Ignore` (Hoşgörülü Mod):** Politika yöneticisi çalışmıyorsa veya webhook servis dışı kaldıysa, API Server doğrulamayı es geçer ve kaynağı oluşturur. Servis sürekliliğinin güvenlik kurallarından daha öncelikli olduğu acil durumlarda veya test ortamlarında tercih edilir.

### 3. Kyverno/OPA API Akış Şeması
```
[Geliştirici / CI-CD]
       │
  (kubectl apply)
       │
       ▼
 [kube-apiserver] ───(HTTP POST / AdmissionReview)───► [Kyverno / Gatekeeper Webhook Pod]
       │                                                      │
       │                                                      │ (Politikaları denetle)
       │                                                      │
 [İsteğe Karar Ver] ◄──(HTTP Response / AdmissionResponse)────┘
  (Kabul veya Red)
```
