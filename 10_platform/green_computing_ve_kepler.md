# Green Computing ve Kepler: Sürdürülebilir Kubernetes

Bulut bilişimin devasa boyutlara ulaşmasıyla birlikte, veri merkezlerinin harcadığı enerji ve bıraktığı karbon ayak izi küresel bir endişe haline gelmiştir. Geleneksel olarak Kubernetes'te **FinOps** (maliyet optimizasyonu) odak noktasıyken, modern (2026) ekosistemde **GreenOps** (sürdürülebilirlik) en az maliyet kadar önemlidir.

Bu noktada CNCF ekosistemine dahil olan **Kepler (Kubernetes-based Efficient Power Level Exporter)**, kümelerimizin ne kadar enerji harcadığını anlamamız için temel taşıdır.

---

## 1. Green Computing ve GreenOps Nedir?

**Green Computing (Yeşil Bilişim)**, donanım kaynaklarının çevreyi en az kirletecek (minimum karbon emisyonu ve enerji tüketimi) şekilde kullanılmasıdır.

**GreenOps**, FinOps'un bir evrimidir. Ancak odak noktası fatura değil, atmosfere salınan CO2 miktarıdır. Bir Kubernetes kümesinde GreenOps prensipleri şunları hedefler:

1. Atıl durumda olan (idle) sunucuların kapatılması (Karpenter ve Cluster Autoscaler ile).
2. Kaynak limitlerinin (requests/limits) aşırı tahsis edilmesinin (overprovisioning) önlenmesi.
3. İş yüklerinin yenilenebilir enerji kaynaklarının daha yoğun kullanıldığı veri merkezi bölgelerine kaydırılması.

---

## 2. Kepler (Kubernetes-based Efficient Power Level Exporter)

Kepler, pod ve node seviyesinde enerji tüketimini ölçmek için eBPF (Extended Berkeley Packet Filter) teknolojisinden yararlanan bir açık kaynak projesidir.

### Nasıl Çalışır?

Fiziksel sunuculardaki (Bare-metal veya Cloud VM) güç tüketim donanımları (Intel RAPL, ACPI) her zaman sanal makinelere veya konteynerlere direkt bilgi aktarmaz. Kepler bu sorunu şöyle çözer:

1. **eBPF:** Çekirdek (Kernel) seviyesinde çalışan pod'ların CPU döngülerini (CPU cycles), bellek erişimlerini (cache misses) ve I/O işlemlerini çok düşük bir yük (overhead) ile yakalar.
2. **Makine Öğrenimi (ML):** Bulut ortamlarında donanım sayaçlarına erişim yoksa, önceden eğitilmiş makine öğrenimi modelleri kullanarak CPU kullanımından "tahmini watt/saat" değerleri üretir.
3. **Prometheus Entegrasyonu:** Tüm bu enerji verilerini Prometheus formatında metrik olarak dışarı sunar.

### Örnek Kepler Mimarisi

```text
[Uygulama Pod'u] -> (CPU/RAM/IO Tüketimi)
       |
       v
[eBPF Programı (Kernel)] -> Performans Sayaçları (Perf Counters)
       |
       v
[Kepler Exporter] -> ML Modeli ile Watt Çevirimi
       |
       v
[Prometheus] -> [Grafana GreenOps Paneli]
```

---

## 3. Kurulum ve Kullanım

Kepler'ı Helm aracılığıyla kümenize kurabilirsiniz:

```bash
# Kepler Helm deposunu ekle
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm repo update

# Kepler'ı kur
helm install kepler kepler/kepler \
  --namespace kepler \
  --create-namespace \
  --set serviceMonitor.enabled=true
```

Kurulum sonrasında Grafana üzerinde bir Dashboard açtığınızda şu gibi metrikleri izleyebilirsiniz:

* `kepler_container_joules_total`: Belirli bir konteynerin harcadığı toplam enerji (Joule cinsinden).
* `kepler_node_core_joules_total`: Tüm fiziksel düğümün (Node) CPU çekirdekleri bazında harcadığı enerji.

### Örnek Senaryo: Enerji Verimli Planlama

Özel bir Kubernetes Scheduler eklentisi kullanarak, Kepler metriklerini baz alabilirsiniz. Eğer kümenizin bir bölümü gece saatlerinde rüzgar/güneş enerjisiyle desteklenen bir bölgedeyse, gecikmeye duyarlı olmayan yığın işlerini (Batch Jobs) o bölgeye kaydırmak gerçek bir **Sürdürülebilirlik** hamlesidir.

---

## 4. FinOps ile GreenOps Arasındaki İnce Çizgi

Bazen daha az maliyetli olan çözüm, çevre için daha zararlı olabilir. Örneğin, eski nesil (ucuz) sunucular kiralayarak faturanızı düşürebilirsiniz; ancak bu eski sunucular aynı işlemi yapmak için yeni nesil sunuculara göre %40 daha fazla elektrik harcayabilir.

Kepler gibi araçlar, FinOps (Maliyet) metrikleri ile GreenOps (Enerji) metriklerini birleştirerek şirketlerin doğru donanım / bulut bölgesi tercihini yapmalarını sağlar.
