# Kabul Politikaları Derinlemesine İnceleme (ValidatingAdmissionPolicy Deep Dive)

Kubernetes kabul denetleyicileri (admission controllers), API sunucusuna gelen isteklerin kimlik doğrulama (authentication) ve yetkilendirme (authorization) adımlarını geçtikten sonra, ancak nesne etki alanına (etcd) kaydedilmeden önce araya giren mekanizmalardır.

Geleneksel olarak, özel doğrulama kuralları uygulamak isteyen ekiplerin Go, Python veya Node.js ile Admission Webhook'ları yazması, bunları küme içinde devreye alması, TLS sertifikalarını yönetmesi ve ağ gecikmelerini/güvenilirlik risklerini üstlenmesi gerekiyordu.

Kubernetes 1.30 ile birlikte kararlı (GA - General Availability) aşamaya ulaşan **ValidatingAdmissionPolicy** (Doğrulama Kabul Politikası), herhangi bir webhook sunucusuna ihtiyaç duymadan, doğrudan API sunucusu içinde **CEL (Common Expression Language)** ifadeleri kullanarak deklaratif kurallar tanımlamanızı sağlar. Bu mekanizma, dışarıya ağ çağrısı yapmadığı için son derece hızlı, güvenli ve düşük maliyetlidir.

---

## 1. ValidatingAdmissionPolicy Bileşenleri

CEL tabanlı doğrulama sistemi iki temel Kubernetes kaynağından oluşur:

1. **ValidatingAdmissionPolicy:** Politikanın hangi kaynaklarla eşleşeceğini, kurallarını ve hata durumlarında hangi CEL ifadelerinin değerlendirileceğini tanımlar.
2. **ValidatingAdmissionPolicyBinding:** Politikanın hangi isim alanlarında (namespace) veya hangi kaynaklarda aktif olacağını, hangi eylemin (`Deny`, `Warn`, `Audit`) tetikleneceğini belirler.

---

## 2. Örnek Senaryolar ve Uygulamalar

Aşağıda, üretim ortamlarında kullanılabilecek tamamen geçerli ve hazır senaryolar yer almaktadır.

### Senaryo 1: Üretim Ortamında Minimum Replika Sayısı Zorunluluğu

Üretim (`production`) ortamındaki Deployment'ların yüksek kullanılabilirlik (High Availability) için en az 3 replikaya sahip olmasını zorunlu kılmak istiyoruz.

* **Politika Kuralı (CEL):** `object.spec.replicas >= 3` ifadesiyle replika sayısı denetlenir ve kural ihlalinde `"Üretim ortamındaki deployment nesneleri en az 3 replikaya sahip olmalıdır."` mesajı döndürülür.
* **Bağlama (Binding):** Politika bağlama nesnesiyle kural sadece `environment: production` etiketine sahip isim alanları (namespaces) üzerinde geçerli kılınır (`validationActions: [Deny]`).

---

### Senaryo 2: Zorunlu Etiket (Label) Kontrolü

Güvenlik ve faturalandırma takibi için kümedeki tüm Pod'ların mutlaka bir `team` etiketine sahip olmasını istiyoruz. Sistem bileşenlerini (`kube-system`) bu kuraldan muaf tutacağız.

* **Politika Kuralı (CEL):** `has(object.metadata.labels) && 'team' in object.metadata.labels` ifadesiyle etiket varlığı kontrol edilir.
* **Bağlama (Binding):** Sistem podlarının etkilenmemesi için `namespaceSelector` filtresinde `kubernetes.io/metadata.name: kube-system` isim alanı kural dışı bırakılır.

---

### Senaryo 3: Sadece Güvenli Konteyner İmaj Kaynaklarına (Registry) İzin Verme

Cluster üzerinde çalışacak container'ların imajlarının yalnızca onaylanmış registry adreslerinden (`gcr.io/` veya `quay.io/`) çekilmesini zorunlu kılmak istiyoruz.

* **Politika Kuralı (CEL):** `object.spec.containers.all(c, c.image.startsWith('gcr.io/') || c.image.startsWith('quay.io/'))` ifadesiyle tüm konteynerlerin imaj kaynakları taranır.
* **Bağlama (Binding):** Küme genelinde `validationActions: [Deny, Warn]` seviyesinde devreye alınarak yetkisiz imajlar engellenir.


---

## 3. Parametrik Politikalar (Parameterization)

CEL doğrulama kurallarını dinamik olarak yapılandırmak mümkündür. Sabit değerleri doğrudan kurala yazmak yerine, bir parametre kaynağı (örneğin bir `ConfigMap` veya özel bir CRD) üzerinden politikaya argüman aktarabilirsiniz.

Aşağıdaki örnekte replika üst sınırını dinamik belirleyen bir parametrik politika gösterilmiştir:

### 1. Politika Tanımı (ConfigMap Parametreli)

Politika içerisinde `paramKind` alanı `ConfigMap` olarak ayarlanır ve kuralda `object.spec.replicas <= int(params.data.maxReplicas)` ifadesiyle dinamik ConfigMap içeriği referans alınır.

#### 2. Parametre Kaynağı (`ConfigMap`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: limit-parameters-config
  namespace: production
data:
  maxReplicas: "5"
```

#### 3. Bağlama Tanımı (Parametre Referanslı)

Bağlama nesnesinde `paramRef.name: limit-parameters-config` referansı verilerek politikanın bu ConfigMap üzerindeki dinamik sınırlara göre çalışması sağlanır.


---

## 4. CEL Değişkenleri ve Bağlamı

Doğrulama ifadelerinde kullanabileceğiniz bazı temel CEL değişkenleri şunlardır:

* `object`: API sunucusuna gönderilen yeni kaynağın kendisi.
* `oldObject`: Kaynak güncellenirken (UPDATE işlemi sırasında) kaynağın eski hali (`CREATE` işlemi sırasında `null` döner).
* `request`: İstek hakkında meta verileri içerir (örneğin istek gönderen kullanıcı adı, API grubu, istek türü).
* `params`: Bağlama dosyasında işaret edilen parametre kaynağı.

---

## 5. Doğrulama Eylemleri (Validation Actions)

Bir istek kurallara uymadığında verilecek tepki `validationActions` listesiyle belirlenir:

* `Deny`: İsteği doğrudan reddeder ve hata mesajını istemciye (kubectl vb.) geri gönderir.
* `Warn`: İsteği kabul eder ancak kullanıcıya bir uyarı mesajı döner.
* `Audit`: İsteği kabul eder ancak Kubernetes audit log'larına bir kayıt ekler.
