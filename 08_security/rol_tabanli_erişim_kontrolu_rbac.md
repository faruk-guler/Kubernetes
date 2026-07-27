# Rol Tabanlı Erişim Kontrolü (RBAC) ve Kimlik Doğrulama

Kubernetes kümelerinde güvenlik, kimliklerin doğrulanması ve her kimliğin yalnızca yapmaya yetkili olduğu işlemleri gerçekleştirebilmesi üzerine inşa edilir. Bu yapının merkezinde **Rol Tabanlı Erişim Kontrolü (Role-Based Access Control - RBAC)** ve harici kimlik doğrulama mekanizmaları yer alır.

---

## 1. RBAC Nedir?

RBAC, küme içindeki kaynaklara (podlar, servisler, gizli bilgiler vb.) kimin, hangi sınırlar dahilinde erişebileceğini "en az yetki" (least privilege) prensibine göre yöneten yetkilendirme (authorization) sistemidir.

### Temel Kavramlar ve Kapsamları

Kubernetes RBAC mimarisinde yetkilendirme dört temel nesne üzerinden gerçekleştirilir:

| Kaynak | Kapsam | Açıklama |
|:---|:---:|:---|
| `Role` | Namespace | Belirli bir isim alanı (namespace) içindeki kaynaklara (pod, configmap vb.) erişim izinlerini tanımlar. |
| `ClusterRole` | Cluster | Tüm küme genelindeki kaynaklara (node, namespace, persistentvolume vb.) veya tüm isim alanlarındaki kaynaklara erişim izinlerini tanımlar. |
| `RoleBinding` | Namespace | Bir `Role` veya `ClusterRole` nesnesini, belirli bir namespace içindeki bir kullanıcıya, gruba veya ServiceAccount'a bağlar. |
| `ClusterRoleBinding` | Cluster | Bir `ClusterRole` nesnesini, tüm küme genelinde geçerli olacak şekilde bir kullanıcıya, gruba veya ServiceAccount'a bağlar. |

---

## 2. RBAC Mantığı: User vs. Service Account

Kubernetes'te istek gönderen ve yetkilendirilen iki temel varlık (subject) türü vardır:

1. **User (Kullanıcı):** Küme dışındaki gerçek kişileri (yöneticiler, geliştiriciler) temsil eder. Kubernetes veritabanında (etcd) bir "User" nesnesi bulunmaz. Kubernetes, kullanıcı kimlik doğrulamayı dış sistemlere (OIDC, X509 sertifikaları) devreder, ancak RBAC kurallarında bu isimleri referans alarak yetkilendirir.
2. **Service Account (Servis Hesabı):** Küme içinde koşan pod'ların ve süreçlerin (örneğin izleme ajanı, CI/CD botu) Kubernetes API sunucusu ile güvenli bir şekilde konuşmasını sağlamak için kullanılır. Tamamen Kubernetes tarafından yönetilir ve namespace bazlıdır.

---

## 3. Temel RBAC Örnekleri

### A. Namespace Bazlı Pod Okuma Rolü (`Role`)

Aşağıdaki örnekte `development` isim alanında pod'ları listeleme, izleme ve loglarını okuma yetkisine sahip bir rol ve bu rolün bir kullanıcıya bağlanması tanımlanmıştır.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [rol_tabanli_erişim_kontrolu_rbac_manifest_2.yaml](../Manifests/07_security/rol_tabanli_erişim_kontrolu_rbac_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Küme Genelinde Node Listeleme Rolü (`ClusterRole`)

Tüm kümedeki fiziksel/sanal sunucuları (Nodes) listelemek için isim alanından bağımsız bir rol ve bağlama oluşturulmalıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [rol_tabanli_erişim_kontrolu_rbac_manifest_3.yaml](../Manifests/07_security/rol_tabanli_erişim_kontrolu_rbac_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. ServiceAccount için RBAC Tanımlama

Bir podun kendi isim alanındaki deployment'ları güncelleyebilmesi için özel bir ServiceAccount oluşturulmalı ve yetkilendirilmelidir:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [rol_tabanli_erişim_kontrolu_rbac_manifest_1.yaml](../Manifests/07_security/rol_tabanli_erişim_kontrolu_rbac_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. ServiceAccount Güvenliği

Varsayılan yapılandırmada oluşturulan her pod, sistemdeki `default` ServiceAccount kimliğini alır ve bu kimliğin token bilgisini diskine mount eder. Güvenliği sıkılaştırmak için şu kurallara uyulmalıdır:

1. **Otomatik Token Yüklemeyi Kapatma:** Eğer podun Kubernetes API sunucusu ile iletişim kurmasına gerek yoksa, token mount işlemi devre dışı bırakılmalıdır:

   ```yaml
   spec:
     automountServiceAccountToken: false
   ```

2. **Özel Hesap Kullanımı:** Her mikroservis için ayrı bir ServiceAccount tanımlanmalı, asla varsayılan (`default`) servis hesabına geniş yetkiler verilmemelidir.

---

## 5. RBAC Yetkilerini Doğrulama (kubectl auth)

Yazdığınız RBAC kurallarını test etmek için kümede değişiklik yapmanıza gerek yoktur. `kubectl auth can-i` komutuyla yetkileri kolayca simüle edebilirsiniz:

```bash
# Belirli bir kullanıcının pod oluşturup oluşturamayacağını sorgulama
kubectl auth can-i create pods --as=developer@example.com -n development

# Bir ServiceAccount'un yetkisini kontrol etme
kubectl auth can-i update deployments \
  --as=system:serviceaccount:production:deploy-bot -n production

# Bir kullanıcının tüm yetkilerini listeleme
kubectl auth can-i --list --as=developer@example.com
```

---

## 6. OIDC (OpenID Connect) ile Kurumsal Kimlik Doğrulama

Bireysel statik X509 sertifikaları (admin sertifikası gibi) yerine kurumsal yapılarda kimlik doğrulama işlemi **OIDC** üzerinden (Google Workspace, Keycloak, Okta, Microsoft Entra ID) yönetilir.

### API Server OIDC Yapılandırması

Kubernetes API sunucusunun OIDC sağlayıcı ile konuşabilmesi için control plane üzerindeki manifest dosyalarında (`/etc/kubernetes/manifests/kube-apiserver.yaml`) şu parametreler ayarlanır:

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --oidc-issuer-url=https://keycloak.example.com/realms/k8s
    - --oidc-client-id=kubernetes-cluster
    - --oidc-username-claim=email
    - --oidc-groups-claim=groups
```

### Dex ve Pinniped ile OIDC Köprüsü

Kurumsal ortamlarda birden fazla kimlik sağlayıcıyı birleştirmek ve OIDC akışını basitleştirmek için CNCF ekosisteminde **Dex** ve **Pinniped** araçları yaygın olarak tercih edilir.

```bash
# Helm ile Dex kurulumu
helm repo add dex https://charts.dexidp.io
helm repo update
helm install dex dex/dex --namespace dex --create-namespace
```

> [!TIP]
> **Pinniped**, kullanıcıların tarayıcı üzerinden kolayca login olup geçici `kubeconfig` token'ları almasını sağlayan modern bir CNCF aracıdır ve kurumsal güvenlik standartlarında öne çıkmaktadır.

---

## 7. Audit Logging (Denetim Günlükleri)

Kümeye kimin eriştiğini, hangi komutları çalıştırdığını ve hangi işlemlerin reddedildiğini izlemek için API Server üzerinde **Audit Policy** yapılandırılmalıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [rol_tabanli_erişim_kontrolu_rbac_manifest_4.yaml](../Manifests/07_security/rol_tabanli_erişim_kontrolu_rbac_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
