# Bölüm 2: Temel Nesneler ve İş Yükleri

Kubernetes kümemizi kurduk ve `kubectl` aracımızı kullanmaya başladık. Artık kümenin içine yavaş yavaş nesneler (objects) ekleyeceğiz. İlk adımımız, bu devasa okyanusu yönetilebilir havuzlara bölmek (Namespace) ve nesnelerimizi işaretlemektir (Labels).

---

## Namespace Yönetimi

Kubernetes kümesi, içinde binlerce farklı uygulamanın, veritabanının ve ekibin barınabileceği devasa bir bilgisayar gibidir. Tüm bu farklı birimlerin birbirine karışmasını engellemek, isim çakışmalarını önlemek ve güvenlik duvarları çekmek için kümeyi mantıksal bölümlere ayırırız. Bu mantıksal bölümlere **Namespace** (İsim Alanı) denir.

Bir apartman düşünün: Kubernetes apartmanın kendisidir, Namespace'ler ise o apartmandaki dairelerdir. Herkes kendi dairesinde bağımsız yaşar.

**Varsayılan (Default) Namespaceler:**
Sıfır bir kurulumda `kubectl get namespaces` yazdığınızda şunları görürsünüz:

* `default`: Namespace belirtmeden bir uygulama kurarsanız buraya düşer.
* `kube-system`: Kubernetes'in kendi sistem bileşenlerinin (DNS, API vs.) çalıştığı, asla dokunulmaması gereken çok kritik alandır.

### İzolasyon ve Kaynak Kotaları

Eğer şirkette 3 farklı yazılım ekibi (Alfa, Beta, Gama) varsa, hepsini `default` namespace'ine tıkıştırmak bir kaostur. En iyi pratik (Best Practice), her ekibe veya her ortama (Dev, Staging, Prod) ayrı bir Namespace vermektir.

```bash
# Yeni bir Namespace oluştur
kubectl create namespace team-alpha
```

**ResourceQuota (Kaynak Kotaları)**
Diyelim ki Alfa ekibi çok hatalı bir kod yazdı ve uygulamanın milyonlarca kopyasını oluşturarak tüm sunucuların CPU'sunu sömürdü. Bu durum Beta ekibini de çökertir. Bunu önlemek için "ResourceQuota" kullanırız:

* *Kural:* "Alfa ekibinin dairesine en fazla 10 Pod, toplam 20 GB RAM ve 8 CPU kotası verilsin."
* Bu sınır aşıldığında Kubernetes Alfa ekibine yeni uygulama kurma izni vermez, ama Beta ekibi güvenle çalışmaya devam eder.

### Context Yönetimi

Sürekli komutların sonuna `-n team-alpha` yazmak yorucudur.

```bash
# Sadece o namespace'teki podları listeleme
kubectl get pods -n team-alpha
```

Bunun yerine, bulunduğunuz odayı (context) kalıcı olarak değiştirebilirsiniz:

```bash
# kubectl'in varsayılan namespace'ini değiştirme (Artık -n yazmaya gerek kalmaz)
kubectl config set-context --current --namespace=team-alpha
```

> [!TIP]
> Önceki bölümde öğrendiğimiz `kubens` (veya `krew install ns`) eklentisiyle bu işlemi `kubectl ns team-alpha` yazarak saniyeler içinde yapabilirsiniz.

---

## Etiketler (Labels) ve Seçiciler (Selectors)

Namespace'ler ile daireleri ayırdık. Peki bir dairenin içindeki yüzlerce eşyayı nasıl bulacağız? İşte burada **Labels (Etiketler)** devreye girer.

Etiketler, Kubernetes nesnelerine yapıştırdığımız anahtar-değer (key-value) şeklindeki post-it notlarıdır.

### Metadata Yönetimi

Uygulamanızı tanımlarken manifest (YAML) dosyasına etiketler eklersiniz:

```yaml
metadata:
  name: frontend-app
  labels:
    tier: frontend
    env: production
    version: v2.0
```

Bu sayede yüzlerce çalışan kod arasında şunu diyebilirsiniz: *"Bana sadece Production ortamında çalışan, v2.0 sürümündeki frontend uygulamalarını getir."*

```bash
# Terminalde etiket ile filtreleme
kubectl get pods -l env=production,tier=frontend
```

### Nesneleri Gruplama ve Eşleştirme Mantığı

Etiketler sadece filtreleme için değil, Kubernetes'in kendi iç mimarisinin çalışması için de bir **omurga** görevi görür.

Kubernetes bileşenleri birbirini **Etiket Seçiciler (Label Selectors)** ile tanır:

* **Service (Yük Dengeleyici):** "Bana gelen internet trafiğini kime yönlendireceğim? Üzerinde `app=backend` etiketi olan tüm Pod'lara yönlendireceğim."
* **Network Policy (Güvenlik Duvarı):** "Sadece üzerinde `tier=database` olan pod'larla konuşmaya izin vereceğim."

> [!IMPORTANT]
> Kubernetes'te hiçbir nesne IP adresi ile birbirine bağlanmaz. Her şey etiketlerle eşleşir. Çünkü IP adresleri sürekli değişir, ancak etiketler sabittir. Etiketleme stratejinizi (örneğin her uygulamaya `app`, `version`, `component` etiketleri koymayı) şirket çapında bir standart haline getirmelisiniz.

Dairemizi (Namespace) kurduk ve eşyalarımızı etiketleme (Labels) kuralını koyduk. Artık o eşyaları, yani gerçek uygulamalarımızı (Pod) dairesine yerleştirmeye hazırız!
