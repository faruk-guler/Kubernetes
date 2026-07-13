# HPA ve VPA ile Pod Ölçeklendirme

Kubernetes'te iş yüklerinin kaynak ihtiyaçları trafik durumuna göre değişkenlik gösterir. Sunucu kaynaklarının verimli kullanılması ve ani yükler altında uygulamanın kesintiye uğramaması için otomatik ölçeklendirme (autoscaling) mekanizmaları kullanılır. Pod seviyesinde ölçeklendirme iki farklı boyutta yapılır: **HPA (Yatay)** ve **VPA (Dikey)**.

---

## 1. HPA (Horizontal Pod Autoscaler - Yatay Ölçekleme)

HPA, CPU veya bellek (RAM) tüketim metriklerine göre **pod kopyalarının sayısını (replicas)** dinamik olarak artıran veya azaltan mekanizmadır.

### Çalışma Mantığı:
HPA, Metrics Server'dan aldığı veriler doğrultusunda şu formüle göre hedef pod sayısını belirler:

$$\text{Target Replicas} = \lceil \text{Current Replicas} \times \frac{\text{Current Metric Value}}{\text{Desired Metric Value}} \rceil$$

### CLI ile HPA Tanımlama:
```bash
# deployment/web-app için CPU %70'i geçtiğinde min 3, max 20 olacak şekilde HPA oluştur:
kubectl autoscale deployment web-app --cpu-percent=70 --min=3 --max=20
```

> [!WARNING]
> HPA'nın doğru çalışabilmesi için pod tanımlarında `resources.requests` (Bölüm 5) değerlerinin mutlaka belirlenmiş olması gerekir. Aksi takdirde yüzdesel hesaplama yapılamaz.

---

## 2. VPA (Vertical Pod Autoscaler - Dikey Ölçekleme)

Her uygulama (Örn: monolitik yapılar veya veritabanları) yatayda genişlemeyi (pod sayısının artmasını) desteklemez. Bu durumlarda pod sayısını artırmak yerine mevcut pod'un **CPU ve RAM kapasitesini (requests/limits)** büyütmek gerekir. VPA tam olarak bunu yapar.

* **Recommender:** Pod'un geçmiş kullanım verilerini inceleyerek en ideal CPU/RAM değerlerini önerir.
* **Updater:** Önerilen yeni değerlerin uygulanması için (mevcut mimaride pod'lar dinamik güncellenemediği için) pod'u yeniden başlatır.
* **VPA Modları:**
  - `Off`: Sadece öneri yapar, müdahale etmez (Goldilocks gibi).
  - `Auto`: Önerileri otomatik olarak uygular (pod'u yeniden başlatarak).

> [!IMPORTANT]
> **Kritik Altın Kural:** Aynı pod üzerinde, aynı metrik (Örn: CPU) için **hem HPA hem de VPA'yı aynı anda KULLANMAYIN**. HPA pod sayısını artırmaya çalışırken, VPA kaynakları artırmaya çalışır; iki denetleyici birbiriyle çelişerek sistemi kararsızlaştırır.

---

## 3. KEDA: Event-Driven Autoscaling (Olay Güdümlü Ölçekleme)

Standart HPA sadece CPU ve RAM metriklerine göre ölçekleme yapabilir. Ancak bazen bir kuyruktaki mesaj sayısına (RabbitMQ, Kafka) veya dış bir veritabanı sorgusuna göre ölçekleme yapmamız gerekir. Bu durumlarda **KEDA** kullanılır.

* KEDA, HPA'yı arka planda kullanarak onu gelişmiş metrik sağlayıcılarla (scalers) entegre eder.
* En büyük avantajı, trafiksiz zamanlarda pod sayısını **sıfıra (0)** düşürebilmesidir (standard HPA en az 1 pod ile çalışmak zorundadır).

📌 **Örnek KEDA Yapılandırması:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [keda_ile_otomatik_olceklendirme_manifest_1.yaml](../Manifests/04_infrastructure/keda_ile_otomatik_olceklendirme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
