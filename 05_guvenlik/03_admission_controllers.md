# Admission Controllers ve Webhook'lar

## 3.1 Admission Controller Nedir?

Kubernetes API Server'a bir istek geldiğinde (örneğin Pod oluşturma), bu istek kaydedilmeden önce iki kritik aşamadan geçer:

1. **Mutating Admission Control:** İsteği değiştirir (sidecar ekler, label ekler)
2. **Validating Admission Control:** İsteği kabul eder ya da reddeder

## 3.2 Webhook Akışı

```
kubectl/ArgoCD → kube-apiserver → Mutating Webhook → Validating Webhook → etcd
                                       ↓                     ↓
                                  (değiştirir)           (onaylar/reddeder)
```

## 3.3 ValidatingWebhookConfiguration

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
    caBundle: <BASE64_CA_CERT>
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail              # Webhook'a ulaşılamazsa reddet
  timeoutSeconds: 10
```

## 3.4 MutatingWebhookConfiguration

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
    caBundle: <BASE64_CA_CERT>
  admissionReviewVersions: ["v1"]
  sideEffects: None
  namespaceSelector:
    matchLabels:
      sidecar-injection: enabled   # Sadece bu label olan namespace'lerde çalış
```

## 3.5 CEL ile ValidatingAdmissionPolicy (2026 Standardı — Webhook Gerektirmez)

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

