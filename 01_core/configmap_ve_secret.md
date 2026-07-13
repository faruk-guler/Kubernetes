# ConfigMap ve Secret Yönetimi

Kubernetes'in "Twelve-Factor App" metodolojisini benimsemesinin en büyük göstergelerinden biri, konfigürasyon (ayarlar) ve kodun birbirinden kesin bir şekilde ayrılmasıdır. Uygulamanızın kaynak kodunun içine veritabanı şifrelerini veya ortam değişkenlerini gömmek yerine, Kubernetes'in sunduğu **ConfigMap** ve **Secret** nesnelerini kullanırız.

---

## 1. ConfigMap: Şifresiz Yapılandırma Dosyaları

ConfigMap, hassas olmayan verileri anahtar-değer (key-value) çiftleri halinde saklamak için kullanılır.

* Veritabanı bağlantı URL'si (örneğin `db-host: pg-cluster.default.svc.cluster.local`)
* Uygulama log seviyesi (`LOG_LEVEL: debug`)
* Nginx veya Redis gibi uygulamaların konfigürasyon dosyaları (`nginx.conf`, `redis.conf`)

### ConfigMap Oluşturma ve Kullanma

Bir ConfigMap'i manifesto (YAML) ile oluşturabiliriz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [configmap_ve_secret_manifest_1.yaml](../Manifests/01_core/configmap_ve_secret_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu ConfigMap'i bir Pod içerisine iki farklı yöntemle enjekte (inject) edebilirsiniz:

1. **Çevre Değişkeni (Environment Variable) Olarak:** `LOG_LEVEL` ve `UI_THEME` değerleri direkt uygulamanın içine işletim sistemi çevre değişkeni olarak aktarılır.
2. **Dosya/Birim (Volume Mount) Olarak:** `settings.json` verisi, konteynerin içindeki bir klasöre fiziksel bir dosya gibi monte edilir. Pod çalıştığı sürece uygulama bu dosyayı okuyabilir.

> 💡 **Meta-veri Aktarımı (Alternative):** Eğer dışarıdan yapılandırma enjekte etmek yerine, doğrudan pod'un kendi çalışma verilerini (Pod Adı, IP'si, CPU/RAM limitleri gibi) çevre değişkeni veya dosya olarak aktarmak istiyorsanız [Downward API](downward_api.md) konusuna göz atabilirsiniz.

---

## 2. Secret: Hassas Verilerin Korunması

Secret'lar, ConfigMap'ler ile tamamen aynı mantıkta çalışır, ancak veritabanı şifreleri, API anahtarları, TLS sertifikaları ve SSH anahtarları gibi **hassas bilgileri** saklamak için tasarlanmıştır.

### Önemli Uyarı: Base64 Şifreleme Değildir

Varsayılan bir Kubernetes Secret YAML'ında veriler sadece **Base64** algoritmasıyla encode edilir (kodlanır).

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-passwords
type: Opaque
data:
  # 's3cr3t' kelimesinin Base64 halidir. Bu şifreleme DEĞİLDİR!
  password: cTNjcjN0
```

Base64 geriye döndürülmesi çok kolay bir kodlama formatıdır. Kümeye erişimi olan ve Secret okuma izni olan herhangi biri, terminale `echo "cTNjcjN0" | base64 --decode` yazarak şifreyi görebilir.

### Secret Yönetiminde Güvenlik Standartları (2026)

Secret'ların sadece Base64 olması güvenlik açıklarına yol açabileceğinden, günümüz modern kümelerinde şu pratikler uygulanır:

#### A. Encryption at Rest (etcd Düzeyinde Şifreleme)

Kubernetes tüm nesneleri `etcd` veritabanında tutar. Varsayılan olarak `etcd` içindeki Secret'lar düz metin (plaintext) olarak durur. Eğer bir saldırgan `etcd` sunucusunun diskini ele geçirirse şifreleri çalabilir. Bunu önlemek için API Server başlatılırken `EncryptionConfiguration` bayrağı aktif edilmeli ve `etcd` diskinde veriler (AES-GCM gibi algoritmalarla) fiziksel olarak şifrelenmelidir.

#### B. RBAC Sınırlandırması

Secret'lara erişim izni, sadece o Secret'a ihtiyacı olan özel ServiceAccount'lara (Uygulama kimliklerine) `Role` ve `RoleBinding` üzerinden verilmelidir. Hiçbir geliştiriciye `kubectl get secrets` yetkisi global olarak verilmemelidir.

#### C. Harici Gizli Veri Yöneticileri (External Secrets)

Günümüzde büyük şirketler Secret'ları Kubernetes içinde tutmak yerine AWS Secrets Manager, Azure Key Vault veya **HashiCorp Vault** gibi dış sistemlerde tutarlar.

* **External Secrets Operator (ESO)** veya **Secrets Store CSI Driver** gibi teknolojiler, dış sistemlerdeki şifreleri güvenli bir şekilde çekerek sadece çalışma zamanında (runtime) bellekte (RAM) Pod'lara sunarlar.

---

## Özet

* **ConfigMap:** Log seviyesi, URL ve tema ayarları gibi herkesin görebileceği konfigürasyonları ayırmak için.
* **Secret:** API anahtarları ve şifreleri tutmak için.
* **Best Practice:** Gizli verileri doğrudan YAML dosyalarına yazıp Git depolarına yüklemeyin (Bkz: GitOps ve Sealed Secrets). Hassas veriler için daima Vault benzeri KMS (Key Management Service) sistemleri entegre edin.
