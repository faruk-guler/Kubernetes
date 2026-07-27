# Kabul Denetleyicileri ve Webhook'lar (Admission Controllers & Webhooks)

Kubernetes API sunucusuna (API Server) gönderilen bir istek (örneğin pod veya servis oluşturma talebi), kimlik doğrulama (Authentication) ve yetkilendirme (RBAC) aşamalarını geçtikten sonra, etcd veritabanına kalıcı olarak yazılmadan önce **Kabul Denetleyicileri (Admission Controllers)** tarafından süzülür. Bu mekanizma, kümenin durumunu korumak, güvenlik politikalarını zorlamak ve kaynakları otomatik olarak manipüle etmek için en güçlü araçtır.

---

## 1. Admission Controller Nedir?

Kabul denetleyicileri iki ana aşamada çalışır:

1. **Mutating Admission Control (Değiştirici Denetim):** Gelen isteğin içeriğini değiştirebilir veya eklemeler yapabilir. Örneğin, bir poda otomatik olarak sidecar konteyneri eklemek veya varsayılan kaynak limitleri tanımlamak bu aşamada gerçekleşir.
2. **Validating Admission Control (Doğrulayıcı Denetim):** İsteğin içeriğini kontrol eder ve şirket kurallarına ya da güvenlik standartlarına uymuyorsa isteği **kabul eder ya da reddeder**. Bu aşamada istek üzerinde herhangi bir değişiklik yapılamaz.

---

## 2. Webhook Akış Mimarisi

Kabul denetimi sürecinde API Server, kendi içindeki yerleşik denetleyicileri çalıştırdıktan sonra dışarıdaki özel web sunucularına (Webhooks) HTTP POST istekleri göndererek onay veya değişiklik talep edebilir:

```
[İstemci Komutu] (kubectl/ArgoCD)
       │
       ▼
 ┌──────────┐     Authentication & Authorization (RBAC)
 │ API Srvr │ ──► (Kimlik ve Yetki Kontrolü)
 └────┬─────┘
      │
      ▼
 ┌──────────┐     Mutating Admission Webhooks
 │  Mutate  │ ──► (İsteği Değiştirir / Sidecar veya Label Ekler)
 └────┬─────┘
      │
      ▼
 ┌──────────┐     Schema Validation
 │ Validate │ ──► (Kubernetes Nesne Şeması Doğrulaması)
 └────┬─────┘
      │
      ▼
 ┌──────────┐     Validating Admission Webhooks
 │ Validate │ ──► (İsteği Onaylar veya Reddeder)
 └────┬─────┘
      │
      ▼
   [ etcd ]       (Veritabanına Kayıt ve Nesne Yaratımı)
```

---

## 3. ValidatingWebhookConfiguration (Doğrulayıcı Webhook Yapılandırması)

Aşağıdaki örnekte, `production` isim alanındaki pod oluşturma ve güncelleme isteklerini doğrulama amacıyla harici bir webhook servisine yönlendiren yapılandırma gösterilmiştir:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [admission_controllers_manifest_1.yaml](../Manifests/07_security/admission_controllers_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. MutatingWebhookConfiguration (Değiştirici Webhook Yapılandırması)

Aşağıdaki örnek, podlara otomatik olarak bir log toplama veya izleme yan konteyneri (sidecar container) enjekte etmek amacıyla çalışan bir değiştirici webhook tanımıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [admission_controllers_manifest_3.yaml](../Manifests/07_security/admission_controllers_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. CEL ile ValidatingAdmissionPolicy (2026 Standartları)

Kubernetes 1.30+ (2026 Standardı) ile birlikte, basit doğrulama kuralları için harici bir web sunucusu (webhook) yazma zorunluluğu ortadan kalkmıştır. **Common Expression Language (CEL)** kullanılarak doğrudan YAML içinde hızlı kurallar tanımlanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [admission_controllers_manifest_2.yaml](../Manifests/07_security/admission_controllers_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

> [!TIP]
> **CEL Avantajı:** CEL politikaları tamamen API Server belleğinde çalıştığı için ağ gecikmesini ortadan kaldırır. Basit mantıksal kurallar için her zaman harici webhook yerine yerleşik CEL tercih edilmelidir.

---

## 6. Kyverno ve OPA Gatekeeper Webhook Entegrasyon Mekanizması

Kyverno ve OPA Gatekeeper gibi gelişmiş bulut yerli (cloud-native) politika motorları, arka planda Kubernetes API Server'ın bu webhook mimarisini otomatik olarak kurar ve yönetir.

### Webhook Kayıt Mantığı

Helm ile kurulum sırasında Kyverno, API sunucusuna kendini kaydetmek için dinamik webhook tanımları oluşturur:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [admission_controllers_manifest_4.yaml](../Manifests/07_security/admission_controllers_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### failurePolicy: Fail vs. Ignore Seçimi

Webhook tanımlarında yer alan `failurePolicy` alanı, olağanüstü durumlarda sistemin nasıl davranacağını belirler:

* **`failurePolicy: Fail` (Güvenli/Sıkı Mod):** Eğer Kyverno/OPA podu çökerse veya webhook sunucusu aşırı yükten dolayı cevap veremezse, API sunucusu **hiçbir yeni kaynağın (örneğin pod veya service) oluşturulmasına izin vermez**. Güvenlik açıklarının oluşmasını önlemek amacıyla kurumsal üretim (production) ortamlarında bu mod kullanılır.
* **`failurePolicy: Ignore` (Hoşgörülü Mod):** Politika yöneticisi webhook sunucusu çalışmıyorsa doğrulama adımı atlanır ve kaynağın oluşturulmasına izin verilir. Servis sürekliliğinin güvenlik kurallarından daha öncelikli olduğu durumlarda veya geliştirme (dev) ortamlarında tercih edilir.

---

## 7. Kyverno/OPA API Akış Şeması

Aşağıdaki şema, bir geliştiricinin istek gönderdiği andan Kyverno webhook'unun kararına kadar olan gRPC/HTTP akışını göstermektedir:

```
[Geliştirici / CI-CD]
       │
  (kubectl apply)
       │
       ▼
 ┌──────────┐       HTTP POST / AdmissionReview
 │ API Srvr │ ──────────────────────────────────────► ┌─────────────────┐
 └────┬─────┘                                         │  Kyverno Podu   │
      │                                               │                 │
      │                                               │ (Politikaları   │
      │                                               │  bellekten      │
      │             HTTP Response / AdmissionResponse │  hızlıca tara)  │
      │ ◄──────────────────────────────────────────── └─────────────────┘
      ▼
[İsteğe Karar Ver] (Kabul/Red)
```
