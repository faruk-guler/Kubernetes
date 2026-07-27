# GPU Paylaşımı ve MIG (Multi-Instance GPU)

Yapay zeka iş yüklerinde en büyük maliyet kalemi ekran kartlarıdır (GPU). Her bir pod için fiziksel olarak ayrı bir GPU atamak, özellikle ufak modeller ve test ortamları için devasa bir kaynak israfına yol açar. Kubernetes üzerinde GPU gücünü en yüksek verimle kullanmak için iki temel yaklaşımımız mevcuttur: **Time-Slicing** (Zaman Dilimleme) ve **MIG** (Multi-Instance GPU - Donanımsal Bölümleme).

---

## 1. Analoji: Time-Slicing vs. MIG

Bu iki yöntem arasındaki farkı anlamak için tek bir kalın ders kitabından (GPU) yararlanarak ödev hazırlamak isteyen 4 öğrenciyi (Pod'ları) hayal edelim:

* **Time-Slicing (Zaman Dilimleme):** Öğrenciler kitabı sırayla okur. Öğretmen her öğrenciye 15 dakika süre verir. 1. öğrenci okur, süresi bitince kitabı 2. öğrenciye devreder.
  * **Sorun:** Eğer öğrencilerden biri kitabı okurken uykuyakalır veya sayfaların üzerine mürekkep dökerse (CUDA Out of Memory / Bellek Aşımı), kitap zarar görür ve sonraki öğrenciler sırasını kullanamaz. Donanımsal bir bellek sınırı olmadığından, bir podun aşırı bellek tüketmesi tüm GPU'yu kilitleyerek diğer podları da çökertecektir.
* **MIG (Multi-Instance GPU):** Öğretmen kalın kitabı maket bıçağıyla 4 bağımsız fasiküle (donanımsal parçalara) ayırır ve her bir fasikülü bir öğrenciye kalıcı olarak teslim eder.
  * **Avantaj:** Artık her öğrencinin elinde kendine ait garantili sayfaları (belleği) ve işlem kapasitesi vardır. Bir öğrencinin kendi fasikülünü yırtması (podun çökmesi) diğer öğrencilerin okuma sürecini asla etkilemez. Donanımsal düzeyde tam bir izolasyon sağlanır.

---

## 2. Time-Slicing (Zaman Dilimleme) Kurulumu

Time-Slicing, donanımsal bölümleme (MIG) desteklemeyen daha eski veya ekonomik GPU'larda (örneğin NVIDIA T4, A10G) tek bir kartı yazılımsal olarak sanal parçalara bölmek için kullanılır.

### Adım 1: Time-Slicing Yapılandırma Dosyası (ConfigMap)

Aşağıdaki ConfigMap ile tek bir GPU'yu yazılımsal olarak 4 adet sanal GPU'ya böleceğimizi belirtiyoruz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gpu_paylasimi_ve_mig_manifest_1.yaml](../Manifests/12_ai/gpu_paylasimi_ve_mig_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Adım 2: GPU Operator Politikasına Enjekte Etme

Oluşturduğumuz ConfigMap'i GPU Operator'a bildirmek için küme politikasını yamalıyoruz (patch):

```bash
kubectl patch clusterpolicy gpu-cluster-policy \
  -n gpu-operator \
  --type merge \
  -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config"}}}}'
```

*Bu işlemin ardından, düğümünüzde 1 adet fiziksel GPU varsa, Kubernetes üzerinde `nvidia.com/gpu: 4` adet kaynak kapasitesi görünmeye başlayacaktır.*

---

## 3. GPU Talep Eden Pod Tanımı

Bir podun içinden GPU kullanabilmek için kaynak limitleri (resources.limits) kısmına ilgili kaynağı ekleriz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gpu_paylasimi_ve_mig_manifest_2.yaml](../Manifests/12_ai/gpu_paylasimi_ve_mig_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. MIG (Multi-Instance GPU) Yapılandırması

NVIDIA A100 ve H100 gibi modern GPU'lar, donanımsal düzeyde bölümlere (instances) ayrılabilir. Her bir MIG bölümünün kendi özel işlemci çekirdekleri (SM) ve HBM bellek kanalları bulunur.

### Örnek A100 (80GB) MIG Profilleri

* `1g.10gb`: GPU gücünün 1/7'si ve 10GB bellek (Maksimum 7 adet oluşturulabilir).
* `2g.20gb`: GPU gücünün 2/7'si ve 20GB bellek.
* `3g.40gb`: GPU gücünün 3/7'si ve 40GB bellek.
* `7g.80gb`: Tüm GPU (Bölünmemiş).

### MIG'i Düğüm Düzeyinde Etkinleştirme

Aşağıdaki etiketleme (labeling) işlemi ile düğüm üzerindeki GPU'yu 7 adet `1g.10gb` profiline böleceğimizi belirtiyoruz:

```bash
# Düğümü etiketle
kubectl label node <gpu-node-adi> nvidia.com/mig.config=all-1g.10gb

# GPU Operator mixed stratejisini aktifleştir
kubectl patch clusterpolicy gpu-cluster-policy \
  -n gpu-operator \
  --type merge \
  -p '{"spec":{"mig":{"strategy":"mixed"}}}'
```

*Artık podlarınızın limitlerine `nvidia.com/mig-1g.10gb: 1` yazarak tam donanımsal izolasyona sahip yapay zeka podları çalıştırabilirsiniz.*

---

## 5. Düğüm Seçimi (Node Selector & Tolerations)

GPU barındıran düğümler oldukça pahalıdır. Sıradan web podlarının yanlışlıkla bu düğümlere planlanarak kaynakları işgal etmesini önlemek amacıyla GPU düğümlerine **Taint** (Leke) uygulanır. GPU podları ise bu tainte karşı **Toleration** (Tolerans) göstererek o sunucularda çalışabilirler.

Ayrıca, spesifik bir GPU mimarisi (Örn: A100) talep etmek için `nodeSelector` veya `nodeAffinity` tanımları kullanılmalıdır:

```yaml
spec:
  nodeSelector:
    nvidia.com/gpu.product: NVIDIA-A100-SXM4-80GB
  tolerations:
  - key: "sku"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
```

---

## 6. Gelişmiş Donanım Yönetimi: DRA (Dynamic Resource Allocation)

Kubernetes v1.31+ sürümüyle birlikte kararlı hale gelen **Dynamic Resource Allocation (DRA)**, GPU ve benzeri karmaşık donanımların podlara atanmasını çok daha esnek hale getirmiştir.

* **Faydası:** Klasik `nvidia.com/gpu` limit tanımı yerine, pod içerisinde *"Bana 200GB/s bant genişliğine sahip ve NVLink bağlantılı iki adet GPU tahsis et"* gibi detaylı özellik (attribute) bazlı donanım rezervasyonları yapılabilmesini sağlar.

---

## 7. GPU İzleme (DCGM Exporter Metrikleri)

NVIDIA GPU Operator ile birlikte gelen **DCGM Exporter**, ekran kartlarının anlık durumunu Prometheus formatında sunar. Kritik PromQL izleme örnekleri:

```promql
# GPU İşlemci Kullanım Yüzdesi
DCGM_FI_DEV_GPU_UTIL{node="gpu-node-1"}

# GPU Frame Buffer (Bellek) Kullanımı (Bayt cinsinden)
DCGM_FI_DEV_FB_USED

# GPU Sıcaklık Takibi (85°C üstü için alarm üretilmelidir)
DCGM_FI_DEV_GPU_TEMP > 85
```

---

## 8. Özet

Küçük inference işlemleri için **Time-Slicing** ekonomik bir çözümken; güvenlik, kararlılık ve bellek garantisi gerektiren kritik üretim ortamlarında **MIG** donanımsal bölümleme tercih edilmelidir. Bir sonraki bölümde, hazırladığımız bu GPU yapılandırmaları üzerinde modellerimizi dış dünyaya nasıl servis edeceğimizi (KServe) inceleyeceğiz.
