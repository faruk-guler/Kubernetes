# Service Account ve Workload Identity Güvenliği (Service Account & Workload Identity)

Kubernetes üzerinde koşan uygulamalarımızın sadece kendi iç dünyalarında çalışması yetmez. Birçok uygulamanın Kubernetes API Server ile konuşması (örneğin pod listesini okumak veya bir ConfigMap'i izlemek) veya harici bulut kaynaklarına (AWS S3, Google Cloud Storage, Azure Key Vault vb.) erişmesi gerekir.

Bu bölümde, uygulama kimliklerinin yönetilmesini sağlayan **Service Account** yapısını, token güvenliğini, projected token modelini ve bulut sağlayıcıları ile entegrasyonu sağlayan **Workload Identity** mimarilerini ele alacağız.

---

## 1. Service Account Nedir?

Kubernetes dünyasında iki tür kimlik (identity) bulunur:

* **User Account (Kullanıcı Hesabı):** Geliştiriciler ve sistem yöneticileri gibi gerçek insanları temsil eder. Küme dışındaki sistemlerle (OIDC, Keycloak, Active Directory vb.) yönetilir.
* **Service Account (Servis Hesabı):** Pod'ların içinde çalışan uygulamaları ve süreçleri temsil eder. Kubernetes veritabanında (etcd) birer nesne olarak saklanır ve doğrudan cluster tarafından yönetilir.

Her pod çalışırken mutlaka bir Service Account kullanır. Eğer pod tanımında açıkça bir hesap belirtmezseniz, Kubernetes o namespace'teki yerleşik `default` Service Account kimliğini poda otomatik olarak atar.

---

## 2. Güvenlik Riski: Otomatik Token Mount Etme

Varsayılan ayarlarla oluşturulan her podun içine, Kubernetes API Server ile konuşabilmesi için otomatik olarak bir Service Account Token'ı (JWT anahtarı) dosya olarak mount edilir. Bu dosya container içinde `/var/run/secrets/kubernetes.io/serviceaccount/token` adresinde saklanır.

> [!WARNING]
> **Güvenlik Riski:** Eğer uygulamanızın Kubernetes API ile konuşmasına gerek yoksa, bu token'ın pod içine mount edilmesi büyük bir güvenlik açığıdır. Uygulamanızda oluşabilecek bir güvenlik zafiyetinde (örneğin Remote Code Execution - RCE), saldırgan pod içine sızıp bu token'ı ele geçirebilir ve API Server üzerinde yetkisiz işlemler gerçekleştirebilir.

Bu riski önlemek için API erişimine ihtiyacı olmayan pod'larda veya Service Account'un kendisinde token mount özelliğini kapatmalıyız:

### Yöntem A: Service Account Düzeyinde Kapatma (Önerilen)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-web-sa
  namespace: production
automountServiceAccountToken: false # Token'ın podlara otomatik bağlanmasını engelle
```

### Yöntem B: Pod Düzeyinde Kapatma

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [service_account_ve_is_yuku_kimligi_manifest_1.yaml](../Manifests/07_security/service_account_ve_is_yuku_kimligi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Projected Token (Kısa Ömürlü ve Güvenli Token)

Eski Kubernetes sürümlerinde oluşturulan Service Account token'ları süresizdi (sonsuza kadar geçerliydi) ve etcd üzerinde statik Secret objeleri olarak saklanıyordu. Çalındığında iptal edilmesi son derece zordu.

Modern Kubernetes mimarisinde artık **Projected Service Account Token** yapısı kullanılır. Bu yöntemde token'lar etcd'ye yazılmaz; doğrudan kubelet tarafından üretilir, kısa ömürlüdür (örneğin 1 saat) ve süresi doldukça kubelet tarafından container içinde otomatik olarak yenilenir.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [service_account_ve_is_yuku_kimligi_manifest_2.yaml](../Manifests/07_security/service_account_ve_is_yuku_kimligi_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Bulut Kaynaklarına Güvenli Erişim: Workload Identity

Geleneksel mimaride pod içindeki bir uygulamanın bulut servislerine (örneğin AWS S3 veya Google Cloud Storage) erişebilmesi için donanım anahtarları (AWS Access Key/Secret Key veya GCP Service Account JSON dosyası) oluşturulup Kubernetes Secret'ları içine yazılırdı. Bu anahtarların çalınma riski yüksektir.

**Workload Identity**, Kubernetes Service Account ile bulut sağlayıcısının IAM (Identity and Access Management) rolleri arasında güven ilişkisi (OIDC federasyonu) kurarak şifresiz ve anahtarsız güvenlik sağlar.

### 1. AWS — IRSA (IAM Roles for Service Accounts)

Kubernetes Service Account nesnesini oluşturduğumuz AWS IAM rolü ile ilişkilendiririz. AWS SDK'ları bu annotation'ı görünce token alışverişini arka planda otomatik yapar:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
  annotations:
    # AWS IAM Rolü ile eşleştirme
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/api-s3-role"
```

### 2. GKE — Workload Identity (Google Cloud)

Google Cloud IAM üzerindeki Service Account (GSA) ile Kubernetes Service Account (KSA) arasında bağ kurma:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
  annotations:
    # Google Cloud Service Account ile eşleştirme
    iam.gke.io/gcp-service-account: "api-gsa@my-project.iam.gserviceaccount.com"
```

### 3. AKS — Azure Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
  annotations:
    # Azure Client ID ile eşleştirme
    azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000"
```

---

## 5. Yetki Doğrulama ve Test Komutları

Bir Service Account'un yetkilerini test etmek için küme yöneticisi olarak aşağıdaki komutları kullanabilirsiniz:

```bash
# 1. 'api-service' hesabının production namespace'inde pod listeleme yetkisi var mı?
kubectl auth can-i list pods \
  --as=system:serviceaccount:production:api-service -n production

# 2. Bu hesabın o namespace'teki tüm yetki listesini sorgulayın
kubectl auth can-i --list \
  --as=system:serviceaccount:production:api-service -n production
```

---

## Özet

Service Account yönetimi, Kubernetes içindeki uygulamaların en zayıf halkası haline gelebilir. En iyi pratik olarak, API erişimi gerektirmeyen tüm podlarda **`automountServiceAccountToken: false`** ayarı yapılmalı ve bulut kaynaklarına erişimde statik şifreler yerine **Workload Identity** tercih edilmelidir.
