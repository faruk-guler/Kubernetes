# Admission Policy Derinlemesine İnceleme

Kubernetes admission controller'lar (kabul denetleyicileri), API sunucusuna gelen isteklerin kimlik doğrulama (authentication) ve yetkilendirme (authorization) adımlarını geçtikten sonra, ancak nesne etki alanına (etcd) kaydedilmeden önce araya giren mekanizmalardır.

Geleneksel olarak, özel doğrulama kuralları uygulamak isteyen ekiplerin Go, Python veya Node.js ile Admission Webhook'ları yazması, bunları cluster içinde devreye alması, TLS sertifikalarını yönetmesi ve ağ gecikmelerini/güvenilirlik risklerini üstlenmesi gerekiyordu.

Kubernetes 1.30 ile birlikte GA (General Availability) aşamasına ulaşan **ValidatingAdmissionPolicy** (Doğrulama Kabul Politikası), herhangi bir webhook sunucusuna ihtiyaç duymadan, doğrudan API sunucusu içinde **CEL (Common Expression Language)** ifadeleri kullanarak deklaratif kurallar tanımlamanızı sağlar. Bu mekanizma, dışarıya ağ çağrısı yapmadığı için son derece hızlı, güvenli ve düşük maliyetlidir.

---

## ValidatingAdmissionPolicy Bileşenleri

CEL tabanlı doğrulama sistemi iki temel Kubernetes kaynağından oluşur:

1. **ValidatingAdmissionPolicy**: Politikanın hangi kaynaklarla eşleşeceğini, kurallarını ve hata durumlarında hangi CEL ifadelerinin değerlendirileceğini tanımlar.
2. **ValidatingAdmissionPolicyBinding**: Politikanın hangi Namespace'lerde veya hangi kaynaklarda aktif olacağını, hangi eylemin (`Deny`, `Warn`, `Audit`) tetikleneceğini belirler.

---

## Örnek Senaryolar ve Uygulama

Aşağıda, üretim ortamlarında kullanılabilecek, tamamen geçerli ve hazır senaryolar yer almaktadır.

### Senaryo 1: Üretim Ortamında Minimum Replika Sayısı Zorunluluğu

Üretim namespace'lerinde çalışan Deployment'ların yüksek kullanılabilirlik (High Availability) için en az 3 replikaya sahip olmasını zorunlu kılmak istiyoruz.

#### 1. Politika Tanımı (ValidatingAdmissionPolicy)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: deployment-min-replicas
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
    - expression: "object.spec.replicas >= 3"
      message: "Uretim ortamindaki Deployment'lar en az 3 replikaya sahip olmalidir."
```

#### 2. Politika Bağlama (ValidatingAdmissionPolicyBinding)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: deployment-min-replicas-binding
spec:
  policyName: deployment-min-replicas
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: production
```

Bu bağlama ile kural sadece `environment: production` etiketine sahip namespace'ler üzerinde geçerli olur.

---

### Senaryo 2: Zorunlu Etiket (Label) Kontrolü

Güvenlik ve faturalandırma takibi için kümedeki tüm Pod'ların mutlaka bir `team` etiketine sahip olmasını istiyoruz. Sistem bileşenlerini (`kube-system`) bu kuraldan muaf tutacağız.

#### 1. Politika Tanımı (ValidatingAdmissionPolicy)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-team-label
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
    - expression: "has(object.metadata.labels) && 'team' in object.metadata.labels"
      message: "Tum Pod'lar 'team' etiketine sahip olmak zorundadir."
```

#### 2. Politika Bağlama (ValidatingAdmissionPolicyBinding)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-team-label-binding
spec:
  policyName: require-team-label
  validationActions: [Deny]
  matchResources:
    excludeResourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      resources: ["pods"]
      namespaces: ["kube-system"]
```

---

### Senaryo 3: Sadece Güvenli Container Image Kaynaklarına İzin Verme

Cluster üzerinde çalışacak container'ların imajlarının yalnızca onaylanmış registry adreslerinden (`gcr.io/` veya `quay.io/`) çekilmesini zorunlu kılmak istiyoruz.

#### 1. Politika Tanımı (ValidatingAdmissionPolicy)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: approved-registries
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, c.image.startsWith('gcr.io/') || c.image.startsWith('quay.io/'))"
      message: "Container imajlari sadece gcr.io/ veya quay.io/ adreslerinden cekilebilir."
```

#### 2. Politika Bağlama (ValidatingAdmissionPolicyBinding)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: approved-registries-binding
spec:
  policyName: approved-registries
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        security-profile: restricted
```

---

## Parametrik Politikalar (Parameterization)

CEL doğrulama kurallarını dinamik olarak yapılandırmak mümkündür. Sabit değerleri doğrudan kodlamak yerine, bir parametre kaynağı (örneğin bir `ConfigMap` veya özel bir CRD) üzerinden politikaya argüman aktarabilirsiniz.

Aşağıdaki örnekte replika üst sınırını belirleyen bir parametrik politika gösterilmiştir:

#### 1. Politika Tanımı (ConfigMap Parametreli)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: replica-limit-policy
spec:
  paramKind:
    apiVersion: v1
    kind: ConfigMap
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
    - expression: "object.spec.replicas <= int(params.data.maxReplicas)"
      message: "Deployment replika sayisi, izin verilen maksimum degeri asamaz."
```

#### 2. Parametre Kaynağı (ConfigMap)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: replica-limit-config
  namespace: default
data:
  maxReplicas: "10"
```

#### 3. Bağlama Tanımı (Parametre Referanslı)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: replica-limit-binding
spec:
  policyName: replica-limit-policy
  validationActions: [Deny]
  paramRef:
    name: replica-limit-config
    namespace: default
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: development
```

---

## CEL Değişkenleri ve Bağlamı

Doğrulama ifadelerinde kullanabileceğiniz bazı temel CEL değişkenleri şunlardır:

* `object`: API sunucusuna gönderilen yeni kaynağın kendisi.
* `oldObject`: Kaynak güncellenirken (UPDATE işlemi sırasında) kaynağın eski hali (`CREATE` işlemi sırasında `null` döner).
* `request`: İstek hakkında meta verileri içerir (örneğin kullanıcı adı, API grubu, istek türü).
* `params`: Bağlama dosyasında işaret edilen parametre kaynağı.

---

## Doğrulama Eylemleri (Validation Actions)

Bir istek kurallara uymadığında verilecek tepki `validationActions` listesiyle belirlenir:

* `Deny`: İsteği doğrudan reddeder ve hata mesajını istemciye (kubectl vb.) geri gönderir.
* `Warn`: İsteği kabul eder ancak kullanıcıya bir uyarı mesajı döner.
* `Audit`: İsteği kabul eder ancak Kubernetes audit log'larına bir kayıt ekler.
