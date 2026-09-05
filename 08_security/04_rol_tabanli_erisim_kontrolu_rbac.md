# Rol Tabanlı Erişim Kontrolü (RBAC) ve Kimlik Doğrulama

Kubernetes kümelerinde güvenlik, kimliklerin doğrulanması ve her kimliğin yalnızca yapmaya yetkili olduğu işlemleri gerçekleştirebilmesi üzerine inşa edilir. Bu yapının merkezinde **Rol Tabanlı Erişim Kontrolü (Role-Based Access Control - RBAC)** ve harici kimlik doğrulama mekanizmaları yer alır.

---

## 1. RBAC Nedir?

RBAC, küme içindeki kaynaklara (podlar, servisler, gizli bilgiler vb.) kimin, hangi sınırlar dahilinde erişebileceğini "en az yetki" (least privilege) prensibine göre yöneten yetkilendirme (authorization) sistemidir.

### Temel Kavramlar ve Kapsamları

Kubernetes RBAC mimarisinde yetkilendirme dört temel nesne üzerinden gerçekleştirilir:

| Kaynak | Kapsam | Açıklama |
| :--- | :---: | :--- |
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

Aşağıdaki örnekte `development` isim alanında pod'ları listeleme, izleme ve loglarını okuma yetkisine sahip bir rol ve bu rolün bir kullanıcıya bağlanması tanımlanmıştır:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: development
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-binding
  namespace: development
subjects:
  - kind: User
    name: "ali@company.com"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### B. Küme Genelinde Node Listeleme Rolü (`ClusterRole`)

Tüm kümedeki fiziksel/sanal sunucuları (Nodes) listelemek için isim alanından bağımsız bir rol ve bağlama oluşturulmalıdır:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-nodes-global
subjects:
  - kind: User
    name: "sysadmin@company.com"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-reader
  apiGroup: rbac.authorization.k8s.io
```

### C. ServiceAccount için RBAC Bağlama

Uygulama podlarının Kubernetes API'si ile konuşabilmesi için atanmış bir `ServiceAccount` nesnesine rol bağlanır. Kullanıcı (`User`) bağlamasından temel farkı, `subjects` altında `kind: ServiceAccount` ve hedef `namespace` belirtilmesidir:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bind-payments-sa
  namespace: production
subjects:
  - kind: ServiceAccount
    name: payments-processor-sa
    namespace: production
roleRef:
  kind: Role
  name: application-operator-role
  apiGroup: rbac.authorization.k8s.io
```

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

## 7. Audit Logging ve Yetki Denetimi

RBAC politikaları *"Kimin hangi işlemi yapmaya yetkisi var?"* (Yetkilendirme / Authorization) sorusunu yanıtlarken, **Audit Logging (Denetim Günlükleri)** *"Kimin ne zaman hangi işlemi yapmaya çalıştığı ve API Server'ın bu isteği kabul mü yoksa ret mi ettiği?"* (Kayıt ve Hesap Verebilirlik / Accounting) sorusunu yanıtlar.

### Denetim Düzeyleri (Audit Levels)

API Server'a gelen istekler belirlenen seviyeye göre günlüğe işlenir:

| Düzey | Kaydedilen Bilgi | Örnek Kullanım Alanı |
| :--- | :--- | :--- |
| **`None`** | Hiçbir log kaydı tutulmaz. | `endpoints`, `healthz` gibi yüksek frekanslı gürültülü sistem okumaları. |
| **`Metadata`** | İstek yapan kullanıcı (`user`), zaman damgası, hedef kaynak ve ad alanı kaydedilir. | Rutin Pod ve Deployment operasyonları. |
| **`Request`** | İstek başlıkları ve istek gövdesi kaydedilir; sunucu cevabı kaydedilmez. | Standart veri girişi ve yönetimsel komutlar. |
| **`RequestResponse`** | İsteğin ve API sunucusunun döndüğü yanıtın tüm içeriği tam gövde olarak saklanır. | `secrets` ve `configmaps` gibi hassas güvenlik nesnelerindeki değişiklikler. |

*(Kube-apiserver üzerinde tam audit-policy.yaml dosyasının yapılandırılması ve sunucu flag tanımları için bkz: **Bölüm 01 — Sistem Sıkılaştırma**).*

---

## Özet

* **Roller:** `Role` namespace seviyesinde kısıtlı kaynaklara erişim verirken, `ClusterRole` küme geneli (Node, PV, Namespace) kaynakları yönetir.
* **Bağlamalar:** `RoleBinding` ve `ClusterRoleBinding`, tanımlanan rolleri kullanıcılara (User), gruplara (Group) veya `ServiceAccount` nesnelerine bağlar.
* **Denetim:** RBAC kurallarının çalıştığını doğrulamak için `kubectl auth can-i` komutu ve yetkisiz girişimleri tespit etmek için **Audit Logging** politikaları devreye alınmalıdır.

