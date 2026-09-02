# Küme Analiz ve İyileştirme Araçları

Bir Kubernetes kümesi (cluster) dışarıdan bakıldığında tamamen sağlıklı görünebilir. Ancak arka planda kaldırılmış (deprecated) API çağrıları yapılıyor, kullanılmayan ve bellek yakan Secret/ConfigMap nesneleri birikiyor veya fark edilmeyen ciddi güvenlik açıkları barındırılıyor olabilir.

Bu bölümde, kümenizin "sağlık röntgenini" çekecek, kaynak israfını önleyecek ve sürümler arası geçişleri kolaylaştıracak en popüler 6 açık kaynaklı analiz ve iyileştirme (sanitizing) aracını ele alacağız.

---

## 1. Popeye: Küme Temizleyici (Sanitizer)

**Popeye**, Kubernetes kümenizi tarayarak kullanılmayan kaynakları, yanlış yapılandırmaları ve potansiyel sorunları tespit eden çok güçlü bir CLI aracıdır. Kümedeki kaynakların durumuna göre size A ile F arasında bir "sağlık notu" (karne) verir.

* **Neleri Tarar?**
  - Kullanılmayan ConfigMap, Secret ve PVC nesneleri.
  - CPU/RAM limitsiz veya request tanımlanmamış pod'lar.
  - Ölü veya yanıt vermeyen servisler (Services).
  - Namespace düzeyinde kaynak limitlerinin aşılması.

### Çalıştırma Komutu:
```bash
# Sadece üretim ortamını taramak için:
kubectl popeye -n production
```

---

## 2. Pluto: Kaldırılan (Deprecated) API Tespiti

Kubernetes sürekli gelişen bir platformdur ve her yeni sürümde bazı API grupları veya nesne sürümleri (Örn: `v1beta1`) kullanımdan kaldırılır. 

**Pluto**, küme yükseltmesi (upgrade) yapmadan önce manifest dosyalarınızda veya kümede çalışan nesnelerde artık kaldırılmış veya güncelliğini yitirmiş API sürümleri olup olmadığını tespit eder.

### Çalıştırma Komutu:
```bash
# Lokal manifest klasörünüzü k8s v1.32 sürümüne göre tarayın:
pluto detect-files -d ./manifests/ --target-versions k8s=v1.32
```

---

## 3. Nova: Helm Grafik Güncellik Analizi

Kümede Helm ile kurulmuş birçok servis (Ingress Controller, Prometheus vb.) bulunabilir. Bu servislerin sürümlerini tek tek takip etmek zordur.

**Nova**, kümede kurulu olan Helm chart'larının güncel sürümlerini depolarından (registries) kontrol eder ve eskiyen bağımlılıkları, yeni sürümleriyle birlikte listeler.

### Çalıştırma Komutu:
```bash
# Kümedeki güncelliğini yitirmiş Helm sürümlerini tara:
nova find --wide
```

---

## 4. KubeCapacity: Kaynak Tüketim Tablosu

**KubeCapacity**, kümedeki düğümlerin (nodes) ve pod'ların rezerve edilen (requests/limits) kaynaklarını ve gerçek anlık kullanımlarını tek bir tabloda birleştirerek kolay okunabilir şekilde sunan basit bir CLI aracıdır.

### Çalıştırma Komutu:
```bash
# Düğüm bazında requests/limits ve gerçek CPU/RAM kullanım yüzdelerini göster:
kubectl resource-capacity --util --pods
```

---

## 5. Goldilocks: CPU/Memory Request Önerisi

Uygulamanız için ne kadar CPU ve RAM `request` veya `limit` değeri vermeniz gerektiğini tahmin etmek zordur. 

**Goldilocks**, pod'larınızın gerçek kullanım metriklerini izleyerek, VPA (Vertical Pod Autoscaler) verileri ışığında en ideal CPU ve RAM değerlerini görsel bir dashboard üzerinden size önerir.

---

## 6. Polaris: Güvenlik ve Standart Taraması

**Polaris**, Kubernetes manifestlerinizi en iyi pratiklere (best practices) göre tarayarak not verir. CPU/RAM limitlerinin unutulması, root kullanıcısıyla çalışan podlar gibi açıkları hem canlı kümede hem de CI/CD aşamasında tespit edebilir.

### Çalıştırma Komutu:
```bash
# Yerel manifest klasörünü tarayıp pretty formatta çıktı al:
polaris audit --audit-path ./k8s-manifests/ --format pretty
```
