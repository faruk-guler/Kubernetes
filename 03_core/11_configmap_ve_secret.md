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

Bu ConfigMap'i bir Pod içerisine iki farklı yöntemle enjekte (inject) edebilirsiniz:

1. **Çevre Değişkeni (Environment Variable) Olarak:** `LOG_LEVEL` ve `UI_THEME` değerleri direkt uygulamanın içine işletim sistemi çevre değişkeni olarak aktarılır.
2. **Dosya/Birim (Volume Mount) Olarak:** `settings.json` verisi, konteynerin içindeki bir klasöre fiziksel bir dosya gibi monte edilir. Pod çalıştığı sürece uygulama bu dosyayı okuyabilir.

> 💡 **Meta-veri Aktarımı (Alternative):** Eğer dışarıdan yapılandırma enjekte etmek yerine, doğrudan pod'un kendi çalışma verilerini (Pod Adı, IP'si, CPU/RAM limitleri gibi) çevre değişkeni veya dosya olarak aktarmak istiyorsanız Downward API konusuna göz atabilirsiniz.

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

## 3. Değiştirilemez (Immutable) ConfigMap ve Secret Yapısı

Kubernetes v1.21 ile kararlı hale gelen **Immutable ConfigMap ve Secret** özelliği, nesnenin `metadata` veya `data` içeriğinin oluşturulduktan sonra değiştirilmesini engeller:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-prod-v1
immutable: true
data:
  DATABASE_TIMEOUT: "30s"
  MAX_CONNECTIONS: "100"
```

### Neden `immutable: true` Kullanmalıyız?

1. **Performans Optimizasyonu:** Normalde her `kubelet`, pod'lara bağlanan ConfigMap'lerdeki değişiklikleri izlemek için API Server üzerinde sürekli bir `watch` bağlantısı tutar. `immutable: true` tanımlandığında kubelet izlemeyi durdurur; bu da binlerce nesne barındıran büyük üretim kümelerinde `kube-apiserver` yükünü ciddi oranda hafifletir.
2. **Kaza ve Bozulmaları Engelleme:** Canlı ortamda çalışan yüzlerce pod'un anlık bir `kubectl edit` veya hatalı bir script sonucu bozulmasını önler. Konfigürasyon değiştiğinde yeni bir isimle (`app-config-prod-v2`) yeni bir ConfigMap üretilir ve kontrollü bir Rolling Update başlatılır.

---

## 4. Pratik İpucu: Tek Komutla Secret Çözme (Base64 Decode)

Kubernetes Secret nesnelerindeki tüm anahtarları tek tek `base64 -d` ile uğraşmadan, doğrudan terminalde çözüp incelemek için `jq` veya `jsonpath` ile pratik bir tek satırlık boru hattı (pipeline) kullanabilirsiniz:

```bash
# Bir Secret içindeki tüm anahtar-değer ikililerini çözüp listeleme
kubectl get secret db-passwords -n default -o json | jq -r '.data | map_values(@base64d)'
```


---

## Özet

* **ConfigMap:** Log seviyesi, URL ve tema ayarları gibi herkesin görebileceği konfigürasyonları ayırmak için.
* **Secret:** API anahtarları ve şifreleri tutmak için.
* **Best Practice:** Gizli verileri doğrudan YAML dosyalarına yazıp Git depolarına yüklemeyin (Bkz: GitOps ve Sealed Secrets). Hassas veriler için daima Vault benzeri KMS (Key Management Service) sistemleri entegre edin.
