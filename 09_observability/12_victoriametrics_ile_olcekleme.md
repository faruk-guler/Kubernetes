# VictoriaMetrics: Yüksek Ölçekli ve Düşük Maliyetli Metrik Yönetimi

Kubernetes dünyasında izleme (monitoring) denince akla ilk gelen standart **Prometheus**'tur. Ancak sisteminiz büyüdükçe, saniyede milyonlarca metrik üretilen ve binlerce podun sürekli açılıp kapandığı (yüksek kardinalite - high cardinality) ortamlarda Prometheus ciddi darboğazlarla karşılaşır:

1. **Bellek Tüketimi (OOM Kills):** Prometheus, tüm time-series index verisini RAM'de tutmaya çalışır. Pod sayısındaki ani bir artışta Prometheus anında OOM (Out Of Memory) yiyerek çöker.
2. **Uzun Vadeli Saklama (Retention) Zorluğu:** Prometheus, yerel diskinde en fazla birkaç haftalık veri saklayacak şekilde tasarlanmıştır. Aylık/yıllık veri saklamak için Thanos veya Cortex gibi karmaşık yan sistemler kurmanız gerekir.
3. **Yüksek Bulut Faturası:** Prometheus'un talep ettiği devasa RAM (64GB-128GB+) ve hızlı NVMe SSD diskler bulut maliyetlerini patlatır.

İşte bu devasa ölçek ve maliyet problemlerini çözmek için endüstrinin yeni gözdelerinden biri **VictoriaMetrics**'tir.

---

## 1. VictoriaMetrics Nedir ve Neden Tercih Edilir?

**VictoriaMetrics**, açık kaynaklı, yüksek performanslı ve yatayda sınırsız ölçeklenebilen bir zaman serisi veritabanı (TSDB) ve izleme sistemidir.

Prometheus API'si ile **%100 uyumludur (Drop-in Replacement)**. Yani mevcut Grafana panellerinizi, Prometheus alert kurallarınızı veya client kütüphanelerinizi değiştirmeden doğrudan VictoriaMetrics'e geçebilirsiniz.

### Prometheus vs. VictoriaMetrics Karşılaştırması

| Kriter | Standart Prometheus | VictoriaMetrics |
| :--- | :--- | :--- |
| **RAM Tüketimi** | Çok Yüksek (Milyon seride 32-64GB+) | **7 ila 10 Kat Daha Az RAM** (~4-8GB) |
| **Disk Sıkıştırma** | Standart (~1.5-2 bayt / veri noktası) | **Çok Yüksek** (~0.4-0.6 bayt / veri noktası) |
| **Sorgu Dili** | PromQL | **MetricsQL** (PromQL'in tümünü kapsar + ekstra fonksiyonlar) |
| **Uzun Vadeli Saklama** | Zor (Thanos/Cortex gerekir) | **Yerleşik (Native)** ve çok kolay yapılandırılır |
| **Yatay Ölçekleme** | Karmaşık (Federation / Thanos) | `vmcluster` mimarisiyle son derece basit |

---

## 2. Mimari Modelleri: Single vs. Cluster

VictoriaMetrics iki farklı mimari seçenekle sunulur:

### A. VictoriaMetrics Single (`vmsingle`)
Tek bir ikili dosyadan (single binary) oluşur. Kümenizdeki metrik sayısı saniyede 1 milyon örneklemenin altındaysa tek bir pod olarak çalışır. Sıfır bakım gerektirir, tek başına çoğu şirketin tüm ihtiyacını karşılar.

### B. VictoriaMetrics Cluster (`vmcluster`)
Devasa ölçekler (saniyede onlarca milyon veri noktası) için bileşenler birbirinden ayrılmıştır:
- **`vmstorage`:** Verileri diskte tutan durum bilgili (stateful) depolama düğümleri.
- **`vminsert`:** Gelen metrikleri `vmstorage` düğümlerine hash bazlı dağıtan durum bilgisi olmayan (stateless) katman.
- **`vmselect`:** Grafana veya kullanıcıdan gelen sorguları işleyip yanıtlayan durum bilgisi olmayan (stateless) hesaplama katmanı.

```
                  ┌────────────────────────┐
                  │   Grafana / Alerts     │
                  └───────────┬────────────┘
                              │ (Sorgular - MetricsQL)
                              ▼
                  ┌────────────────────────┐
                  │        vmselect        │
                  └───────────┬────────────┘
                              │
                              ▼
┌───────────────┐ (Veri)  ┌───────────────┐ (Dağıtım) ┌───────────────┐
│    vmagent    │ ──────► │   vminsert    │ ────────► │   vmstorage   │
└───────────────┘         └───────────────┘           └───────────────┘
  (Metrik Toplayıcı)                                    (Kalıcı Diskler)
```

---

## 3. `vmagent`: Hafif ve Akıllı Metrik Toplayıcı

Kubernetes üzerinde Prometheus yerine genellikle **`vmagent`** bileşeni kullanılır. 

`vmagent`, Prometheus'un `scrape` (metrik kazıma) konfigürasyonlarını ve `ServiceMonitor` / `PodMonitor` CRD nesnelerini doğrudan anlar. 
- Prometheus'a kıyasla **%75 daha az bellek ve CPU** tüketir.
- Eğer merkezi izleme sunucusu geçici olarak erişilemez olursa, topladığı metrikleri yerel belleğinde veya diskinde kuyruğa alır; bağlantı geldiğinde veri kaybetmeden merkeze aktarır.

---

## 4. Kubernetes Üzerinde Kurulum (VictoriaMetrics Operator)

VictoriaMetrics Operator, Prometheus Operator'ın yaptığı her şeyi yapar ve `ServiceMonitor` nesneleriyle birebir çalışır:

```bash
# Helm deposunu ekleyin
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

# VictoriaMetrics K8s Stack (Operator + Grafana + vmagent + Alertmanager)
helm install vm-stack vm/victoria-metrics-k8s-stack \
  --namespace monitoring \
  --create-namespace \
  --set vmsingle.spec.retentionPeriod="12" # 12 Aylık Veri Saklama Süresi!
```

Sadece `retentionPeriod: "12"` parametresini girerek, hiçbir ek yan sisteme (Thanos vb.) ihtiyaç duymadan 1 yıl boyunca geçmiş verileri saklayabilirsiniz.

---

## 5. MetricsQL: PromQL'in Güçlendirilmiş Hali

VictoriaMetrics, PromQL'in yetersiz kaldığı noktalarda geliştiricilere hayat kurtaran fonksiyonlar sunar:

- **Dinamik Aralık:** `rate(http_requests_total[1d:1h])` gibi esnek sorgulama.
- **`rollup_rate`:** Ani trafik artışlarını (spikes) kaçırmadan doğru ortalama hesaplama.
- **Alt Sorgular:** Karmaşık pencereleme ve anomalileri çok daha az CPU harcayarak saniyeler içinde hesaplayabilme.

## Özet
Kümeniz büyüdükçe "Prometheus yine OOM yedi" bildirimlerinden ve devasa AWS/GCP disk faturalarından bunaldıysanız, **VictoriaMetrics** hem SRE ekiplerinin geceleri rahat uyumasını sağlayan hem de şirket bütçesini ferahlatan modern bir kurtarıcıdır.
