# Pod ve Kubernetes Nesneleri (Pods & Objects)

Kubernetes'te her şey bir **nesne (object)** olarak tanımlanır. Bu nesneler YAML veya JSON formatında bildirilir ve API Server tarafından yönetilir. En temel nesne **Pod**'dur; geri kalan her şey pod'ları farklı şekillerde yönetmek ve kontrol etmek için var olur.

---

## 1. Pod Nedir?

Pod, Kubernetes'in en küçük dağıtım birimidir. Bir pod içinde **bir veya daha fazla container** çalışabilir; bu container'lar aynı ağ (network namespace) ve depolama alanını (volumes) paylaşır.

* **Tekil Konteyner Modeli:** Pod başına bir konteyner modeli, en yaygın kullanılan modeldir.
* **Çoklu Konteyner Modeli:** İki veya daha fazla konteynerin sıkı sıkıya bağlı olarak birlikte çalışması gerektiğinde (örneğin; asıl uygulamanın yanına bir log toplayıcı veya proxy yerleştirilmesi - Sidecar deseni) kullanılır.

> [!IMPORTANT]
> Pod'lar doğrudan tekil olarak oluşturulmaz. Genellikle her zaman bir **Deployment**, **StatefulSet** veya **DaemonSet** üzerinden yönetilir. Aksi hâlde pod çöktüğünde veya düğüm kapandığında yeniden başlatılmaz veya başka düğüme taşınmaz.

---

## 2. Stateless İş Yükleri: Deployment

Deployment, stateless (durumsuz) uygulamalar için en yaygın kullanılan nesnedir. Pod'ları ReplicaSet üzerinden yönetir, sıfır kesintili güncelleme (rolling update) ve versiyon geri alma (rollback) yetenekleri sağlar.

### Rollout ve Revizyon Yönetimi Komutları

```bash
# Güncelleme durumunu canlı olarak izleyin
kubectl rollout status deployment/web-app -n production

# Dağıtım revizyon geçmişini görüntüleyin
kubectl rollout history deployment/web-app -n production

# Bir önceki versiyona geri dönün (Rollback)
kubectl rollout undo deployment/web-app -n production

# Belirli bir revizyona (versiyona) geri dönün
kubectl rollout undo deployment/web-app --to-revision=2 -n production

# Güncellemeyi duraklatın / devam ettirin
kubectl rollout pause deployment/web-app -n production
kubectl rollout resume deployment/web-app -n production

# Pod'ları yeniden başlatın (İmaj değişmeden pod'ları yenilemek için)
kubectl rollout restart deployment/web-app -n production
```

---

## 3. Stateful İş Yükleri: StatefulSet

StatefulSet, veritabanları veya durum bilgisi saklayan (Stateful) uygulamalar içindir. Her pod sabit bir ağ kimliği ve kalıcı depolama alanı (Volume) alır.

* **Pod İsimleri Sabit ve Öngörülebilirdir:** `db-0`, `db-1`, `db-2`
* **Sıralı Başlatma:** `db-0` tamamen hazır olmadan `db-1` başlatılmaz.
* **Sıralı Silme:** Ters sırayla (`db-2` ──► `db-1` ──► `db-0`) güvenli bir şekilde kapatılır.

---

## 4. Altyapı İş Yükleri: DaemonSet

DaemonSet, **her düğümde (node) tam olarak bir pod** çalıştıracağını garanti eder. Kümeye yeni bir düğüm eklendiğinde pod otomatik olarak o düğüm üzerinde de başlatılır.

* **Kullanım Alanları:** Log toplayıcılar (Fluent Bit), metrik toplayıcılar (node-exporter), CNI ağ eklentileri (Cilium, Calico) ve güvenlik izleme yazılımları (Falco).

---

## 5. Kısa Süreli İş Yükleri: Job & CronJob

Sürekli çalışması gerekmeyen, bir görevi tamamlayıp kapanması gereken iş yükleri için kullanılır.

* **Job:** Tek seferlik görevleri çalıştırır (Örn: Veritabanı şeması güncelleme, veri taşıma).
* **CronJob:** Belirli zaman aralıklarında (cron formatında) tekrarlanan görevleri çalıştırır (Örn: Her gece saat 03:00'te yedek alma).

---

## 6. Etiket (Label) ve Açıklama (Annotation)

Kubernetes nesnelerine ek bilgi (metadata) eklemek için iki temel parametremiz vardır: **Label** ve **Annotation**. Her ikisi de anahtar-değer (key-value) eşleşmesiyle çalışsa da kullanım amaçları tamamen farklıdır.

### Label ve Annotation Arasındaki Temel Fark

* **Label (Etiket):** Kubernetes nesnelerini gruplamak, filtrelemek ve nesneler arasında bağ kurmak için kullanılır. Örneğin, bir `Service` nesnesinin trafiği hangi pod'lara yönlendireceğini seçmesi (`spec.selector`) etiketler sayesinde olur. Yanlışlıkla bir etiketi silmek, uygulamanın trafiğinin kesilmesine yol açabilir.
* **Annotation (Açıklama):** Herhangi bir nesneyi gruplama veya seçme (selector) amacıyla kullanmayacağımız, sadece nesneyle ilgili ek/tanımlayıcı bilgi sunmak istediğimiz durumlarda kullanılır. Harici araçlar (Ingress Controller, cert-manager vb.) tarafından okunacak yapılandırmalar da buraya yazılır.

### Örnek Adlandırma Kuralları ve Sözdizimi (Syntax)

Bir annotation anahtarı şu kurallara uymalıdır:

```
company.com/notification-email : admin@company.com
└─Prefix─┘ └──────Key─────┘   └─────Value─────┘
```

* **Prefix (Önek):** Zorunlu değildir. Ancak çakışmaları önlemek için önek kullanılması (Örn: `nginx.ingress.kubernetes.io/...`) önerilir.
* **Key (Anahtar):** Maksimum 63 karakter olmalı, alfanümerik başlamalı ve bitmelidir.
* **Value (Değer):** Boyut sınırı olmaksızın daha uzun verileri (JSON veya YAML gibi) barındırabilir.

### Yönetim Komutları

```bash
# Label ile listeleme ve filtreleme
kubectl get pods -l app=web-app
kubectl get pods -l env=prod,tier=frontend
kubectl get pods -l 'env in (prod,staging)'

# Çalışan pod'a dinamik olarak label ekleme ve silme
kubectl label pod my-pod env=prod
kubectl label pod my-pod env-          # Anahtarın sonuna '-' koyarak silinir

# Çalışan pod'a dinamik olarak annotation ekleme ve silme
kubectl annotate pod my-pod owner=platform-team
kubectl annotate pod my-pod owner-   # Anahtarın sonuna '-' koyarak silinir
```

### Karşılaştırma Özeti

| Özellik | Label (Etiket) | Annotation (Açıklama) |
| :--- | :--- | :--- |
| **Ana Amacı** | Gruplama, Seçim (Selector) | Ek bilgi, Metadata, Harici Yapılandırma |
| **Sorgulanabilir mi?** | Evet (`-l` parametresi ile) | Hayır (Filtreleme yapılamaz) |
| **Boyut Sınırı** | Kısa (Maksimum 63 karakter) | Büyük boyutlu veri veya şablon tutabilir |
| **Örnek Kullanım** | `app: nginx`, `env: prod` | `owner: devops`, `nginx.ingress.kubernetes.io/ssl-redirect: "true"` |

---

## 7. Özel Kayıt Defteri (Private Registry) Erişimi

Eğer imajınız GitHub Packages, Docker Hub Private Registry veya GitLab Container Registry gibi özel bir alanda barındırılıyorsa, pod'un bu imajı çekebilmesi için kimlik bilgisi içeren bir `Secret` tanımlanmalıdır:

```bash
# Private registry için secret oluştur
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=yazilimci \
  --docker-password=github_token_degeri \
  -n production
```

Bu secret, pod tanımı altında `imagePullSecrets` alanına eklenmelidir:

```yaml
spec:
  imagePullSecrets:
  - name: regcred
  containers:
  - name: my-private-app
    image: ghcr.io/company/private-app:v1.0.0
```

---

## Özet

Kubernetes üzerinde tüm iş yüklerinizi organize etmek için nesnelerin gücünden faydalanırız. **Pod**'lar doğrudan oluşturulmak yerine, kullanım amacına göre (Stateless ise **Deployment**, Stateful ise **StatefulSet**, Node Agent ise **DaemonSet**) uygun üst kontrolörler (controllers) aracılığıyla ayağa kaldırılmalıdır.
