# OPA Gatekeeper ile Politika (Policy) Yönetimi

Kubernetes kümelerinde "Kim ne yapabilir?" sorusunun cevabını RBAC (Role-Based Access Control) verir. Ancak, **"Neler yapılabilir ve hangi şartlarda yapılabilir?"** sorusunun cevabını (Örneğin: "Hiçbir pod root olarak çalışamaz", "Tüm imajlar özel registry'mizden gelmelidir") **Admission Controller**'lar ve Politika Motorları verir.

Bu alanda endüstrinin iki devi vardır: **Kyverno** ve **OPA Gatekeeper**.

---

## 1. OPA Gatekeeper Nedir?

**OPA (Open Policy Agent)**, CNCF Graduated (mezun) bir projedir ve sadece Kubernetes değil, Envoy, Terraform, CI/CD süreçleri gibi tüm IT altyapısı için genel amaçlı bir politika motorudur.

**Gatekeeper**, OPA'in Kubernetes Admission Webhook (Validating/Mutating) bileşeni olarak özel olarak tasarlanmış entegrasyonudur. 

### Kyverno vs. OPA Gatekeeper

| Özellik | Kyverno | OPA Gatekeeper |
| :--- | :--- | :--- |
| **Dil** | Standart Kubernetes YAML | **Rego** (Özel politika dili) |
| **Öğrenme Eğrisi** | Çok Düşük (K8s bilen hemen yazar) | Yüksek (Rego dilini öğrenmek gerekir) |
| **Ekosistem** | Sadece Kubernetes | K8s, Terraform, Envoy, Kafka vb. |
| **Performans** | Orta / Yüksek | Çok Yüksek (Çok büyük kümelerde daha iyidir) |
| **Kütüphane (Hazır Kurallar)**| Çok geniş | Çok geniş (Gatekeeper Library) |

> **SRE Kuralı:** Eğer şirketinizde politikaları zaten Terraform veya CI/CD için Rego diliyle yazıyorsanız, Kubernetes için OPA Gatekeeper seçmelisiniz. Eğer sadece Kubernetes için bir araca ihtiyacınız varsa Kyverno kullanımı çok daha kolaydır.

---

## 2. Gatekeeper Kurulumu

Helm kullanarak kurulumu oldukça basittir:
```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper/gatekeeper --name-template=gatekeeper --namespace gatekeeper-system --create-namespace
```

---

## 3. Gatekeeper Mimarisi (ConstraintTemplate ve Constraint)

Gatekeeper'ın çalışma mantığı 2 aşamalıdır. Doğrudan kural yazıp uygulamayız, bunun yerine bir "Şablon" oluştururuz.

### A. ConstraintTemplate (Kural Şablonu)
Bu dosya, Rego dilinde yazılmış asıl mantığı (kodlamayı) içerir ve kuralın alacağı parametreleri tanımlar.
Örneğin, "Gerekli Etiketler (RequiredLabels)" adında bir şablon oluşturduğumuzu düşünün. Bu şablon "Verilen nesnede belirtilen etiket var mı?" diye kontrol eder. (Hangi etiketi kontrol edeceğini burada söylemeyiz).

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg, "details": {"missing_labels": missing}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("you must provide labels: %v", [missing])
        }
```

### B. Constraint (Kısıtlama / Uygulama)
ConstraintTemplate (Şablon) kümeye yüklendikten sonra, bu şablonu kullanarak (artık özel bir CRD oluşmuştur) kuralı somutlaştırırız.

Aşağıdaki Constraint, önceki şablonu çağırır ve **"Tüm Namespace'lerde 'gatekeeper' etiketi zorunlu olsun"** kuralını koyar:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: ns-must-have-gk
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
  parameters:
    labels: ["gatekeeper"]
```

Eğer bu kural uygulandıktan sonra içinde `gatekeeper` etiketi olmayan bir namespace oluşturmaya çalışırsanız, Kubernetes API Server isteğinizi reddedecektir.

---

## 4. Hazır Kural Kütüphanesi (Gatekeeper Library)

Rego öğrenmek zaman alıcıdır. Bu nedenle OPA topluluğu yüzlerce hazır `ConstraintTemplate` oluşturmuştur. Bu depodan ihtiyacınız olan şablonları indirip doğrudan kullanabilirsiniz.

Popüler şablonlar:
- İmajların belirli kayıt defterlerinden (Registry) gelmesini zorunlu kılma (`K8sAllowedRepos`)
- Podların root yetkisi almasını engelleme (`K8sPSPPrivilegedContainer`)
- CPU/RAM limitsiz pod açılmasını engelleme (`K8sContainerLimits`)

**Kütüphane Adresi:** [https://github.com/open-policy-agent/gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library)

## Özet
OPA Gatekeeper, özellikle karmaşık ve devasa Kubernetes kümeleri yöneten büyük ölçekli Enterprise firmalar (bankalar, telekomünikasyon şirketleri vb.) için standart politika aracıdır. Rego dilinin esnekliği, sadece limitleri aşan değil hayal edebileceğiniz hemen her türlü doğrulama ve kısıtlamayı Kubernetes API seviyesinde uygulamanıza olanak tanır.
