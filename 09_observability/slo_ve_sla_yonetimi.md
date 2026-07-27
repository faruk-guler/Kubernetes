# Hizmet Seviyesi Hedefleri ve Hata Bütçesi Yönetimi (SLO & SLA Management)

Kubernetes kümeniz milyonlarca metrik ve log üretiyor olabilir; ancak bu veriler "Kullanıcı deneyimi iyi mi yoksa kötü mü?" sorusuna net bir yanıt veremiyorsa, gözlemlenebilirlik altyapınız eksik demektir. Google Site Reliability Engineering (SRE) metodolojisinde bu soruyu yanıtlamak için **SLI, SLO, SLA ve Hata Bütçesi (Error Budget)** kavramları kullanılır.

---

## 1. Temel Kavramlar

| Kavram | Tanım | Pratik Örnek |
|:---|:---|:---|
| **SLA (Service Level Agreement)** | Müşteriyle yapılan, uyulmadığında cezai şartlar içeren yasal/ticari taahhüttür. | "Uygulama aylık %99.9 oranında çalışır, aksi halde ücret iadesi yapılır." |
| **SLO (Service Level Objective)** | SLA ihlalini önlemek amacıyla mühendislik ekipleri için belirlenmiş iç hedeftir. | "Uygulama aylık %99.95 başarılı yanıt oranıyla çalışmalıdır." |
| **SLI (Service Level Indicator)** | Hizmet kalitesini gösteren anlık ve matematiksel metriktir. | "Son 5 dakikadaki başarılı isteklerin toplam isteklere oranı." |
| **Error Budget (Hata Bütçesi)** | Belirlenen SLO hedefine göre, sisteme izin verilen maksimum hata veya kesinti süresidir. | "%99.9 SLO için aylık maksimum 43.2 dakika kesinti hakkı." |

### Hata Bütçesi (Error Budget) Hesaplama Mantığı

30 günlük bir ay için (30 gün × 24 saat × 60 dakika = 43,200 dakika):

* **%99.9 Uptime SLO Hedefi:**

    $43,200 \text{ dk} \times (1 - 0.999) = 43.2 \text{ dakika/ay} \text{ kesinti hakkı.}$

* **%99.99 Uptime SLO Hedefi:**

    $43,200 \text{ dk} \times (1 - 0.9999) = 4.32 \text{ dakika/ay} \text{ kesinti hakkı.}$

> [!IMPORTANT]
> SLO hedeflerine birer adet "9" eklemek (Örn: %99.9'dan %99.99'a geçmek), hata bütçesini 10 kat daraltır ve altyapı maliyetlerini katlayarak artırır. Bu nedenle hedefler teknik ekiplerce değil, iş birimleriyle ortak belirlenmelidir.

---

## 2. PromQL ile SLI Tasarımları

İyi bir SLI, sistem performansını değil doğrudan kullanıcı memnuniyetini ölçmelidir.

### A. Erişilebilirlik SLI (Availability)

Toplam istekler içindeki HTTP 5xx olmayan (başarılı) isteklerin oranı:

```promql
sum(rate(http_requests_total{code!~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

### B. Performans SLI (Latency)

Toplam istekler içindeki, 300 milisaniyenin altında yanıtlanan isteklerin oranı:

```promql
sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
/
sum(rate(http_request_duration_seconds_count[5m]))
```

### C. Hata Bütçesi Durum Sorgusu (Son 30 Gün)

Kalan hata bütçesi yüzdesini hesaplamak için PromQL sorgusu:

```promql
(
  1 - (
    sum(rate(http_requests_total{code=~"5.."}[30d]))
    /
    sum(rate(http_requests_total[30d]))
  )
) / (1 - 0.999) # 0.999 = SLO Hedefimiz (%99.9)
```

---

## 3. Pyrra ile Kubernetes-Native SLO Yönetimi

**Pyrra**, SLO hedeflerini Kubernetes üzerinde birer CRD (Custom Resource) olarak tanımlamanızı sağlayan ve bu tanımlara göre otomatik olarak Prometheus uyarı kurallarını (Alerting Rules), ön-hesaplama kurallarını (Recording Rules) ve Grafana panellerini üreten açık kaynaklı bir SRE aracıdır.

### Pyrra Kurulumu

```bash
kubectl apply -f https://raw.githubusercontent.com/pyrra-dev/pyrra/main/config/operator/deploy.yaml
```

### Örnek `ServiceLevelObjective` CRD Tanımı

Aşağıdaki YAML, `billing-api` servisi için %99.9 oranında başarılı yanıt vermesini zorunlu kılan SLO tanımıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [slo_ve_sla_yonetimi_manifest_1.yaml](../Manifests/08_observability/slo_ve_sla_yonetimi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Pyrra bu dosyayı okuduğunda arka planda Prometheus için karmaşık hata bütçesi tüketim alarmlarını otomatik yazar.

---

## 4. Multi-Window, Multi-Burn Rate Alerting (Tüketim Hızı Alarmları)

Geleneksel alarmlar statik eşik değerleriyle çalışır (Örn: Hata oranı %1'i geçerse uyar). Ancak bu durum geceleri gereksiz uyandırmalara veya yavaş yavaş biten hata bütçelerinin fark edilmemesine yol açar.

Google SRE ekibinin önerisi **Burn Rate (Hata Bütçesi Tüketim Hızı)** tabanlı alarmlardır:

* **Burn Rate = 1:** Hata bütçesi tam olarak 30 günde tükenecektir (Normal durum).
* **Burn Rate = 14.4:** Hata bütçesi sadece 50 saatte tamamen tükenecektir (Acil durum).

### Çoklu Pencere Tüketim Sıklığı Tablosu

| Tüketim Hızı (Burn Rate) | Bütçenin Tamamen Erime Süresi | Kısa Pencere | Uzun Pencere | Alarm Önceliği |
|:---:|:---:|:---:|:---:|:---:|
| **14.4x** | 2 Saat | 5 Dakika | 1 Saat | 🔴 Pager (Kritik) |
| **6.0x** | 5 Saat | 30 Dakika | 6 Saat | 🟠 Ticket (Yüksek) |
| **3.0x** | 10 Saat | 6 Saat | 1 Gün | 🟡 Slack (Orta) |
| **1.0x** | 30 Gün | - | - | ✅ Normal |

*Önemli:* Hem kısa hem de uzun penceredeki hata oranları eşik değerini aştığında alarm tetiklenir. Bu sayede, anlık olarak yükselip hemen düzelen (anlık dalgalanma) sahte alarmlar elenmiş olur (Alert Fatigue engellenir).

---

## 5. Grafana SLO Dashboard Görselleştirmesi

Pyrra arayüzü ve Grafana üzerinde tanımlanan SLO'lar için otomatik oluşan hazır paneller sayesinde ekipler anlık olarak şu metrikleri izler:

1. **Error Budget Remaining (Kalan Hata Bütçesi):** Yeşil (Güvenli) veya Kırmızı (Bütçe tükendi).
2. **Burn Rate Gauge:** Bütçenin o andaki erime hızı.
3. **Uptime Trend:** 30 günlük kayan penceredeki başarı grafiği.

---

## 6. SRE SLO Kültürü ve Hata Bütçesi Politikaları

SLO hedefleri koymak teknik bir işlemden ziyade kurumsal bir kültürdür:

* **Asla %100 Hedeflemeyin:** %100 kararlılık hedefi koymak, sisteme yeni özellikler (features) eklemeyi, güncellemeler yapmayı tamamen yasaklamak demektir.
* **Hata Bütçesi Tükendiğinde Ne Olur?** Eğer bir servisin hata bütçesi (Örn: %99.9) ay dolmadan sıfırlanırsa, **yeni kod yayına alma (deployment) işlemleri tamamen durdurulur**. Tüm yazılım ekibi sadece sistemin kararlılığını artıracak refactor ve hata giderme işlerine odaklanır. Bu kurala **Error Budget Policy** denir.
* **Her Alarma Bir Runbook:** SLO tabanlı bir alarm tetiklendiğinde, alarm bildiriminin içinde alarmla ilgilenecek mühendisin izleyeceği adımları içeren bir **Runbook** linki yer almalıdır.
