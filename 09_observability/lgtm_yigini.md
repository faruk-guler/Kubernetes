# LGTM Yığını (Grafana LGTM Stack) ile Gözlemlenebilirlik

"Sistemimiz çalışıyor gibi görünüyor" demek, modern mikroservis ve bulut mimarilerinde yeterli değildir. Bir uygulamanın veya altyapının iç durumunu, darboğazlarını, hata oranlarını ve kaynak tüketimlerini anlık olarak izleyebilmemiz gerekir. CNCF ekosisteminde gözlemlenebilirliğin (observability) modern standardı **Grafana LGTM Stack (Loki, Grafana, Tempo, Mimir)** yığınıdır.

---

## 1. LGTM Yığını Nedir?

LGTM, gözlemlenebilirliğin üç temel direği olan **Metrikler, Loglar ve İzler (Traces)** kavramlarını tek bir platformda birleştiren bileşenlerden oluşur:

| Harf | Bileşen | Temel Görevi |
|:---:|:---|:---|
| **L** | **Loki** | Log (günlük) toplama ve sorgulama sistemi. Logları indekslemek yerine sadece etiketlediği için çok az disk ve işlemci tüketir. |
| **G** | **Grafana** | Metrikleri, logları ve trace'leri tek bir ekranda birleştiren görselleştirme arayüzü (dashboard). |
| **T** | **Tempo** | Dağıtık izleme (distributed tracing) verilerini depolayan, isteklerin servisler arasındaki yolculuğunu gösteren sistem. |
| **M** | **Mimir** | Milyonlarca metriğin uzun süreli depolanmasını sağlayan, Prometheus uyumlu ve yüksek ölçeklenebilir metrik veritabanı. |

### Geleneksel İzleme (EFK Stack) ile Karşılaştırma

Modern LGTM mimarisinden önce sektör standardı olan **EFK Stack (Elasticsearch, Fluentd, Kibana)** yapısını bilmek önemlidir:

* **Elasticsearch:** Loglardaki her kelimeyi tam metin (full-text) olarak indekslediği için devasa RAM ve disk alanı tüketir.
* **Grafana Loki:** Sadece logların kaynak etiketlerini (örneğin `app=payment-service`) indeksler. Bu yaklaşım, EFK yığınına kıyasla **%90 daha az depolama alanı** ve sunucu kaynağı tüketilmesini sağlar.

---

## 2. Kube-Prometheus-Stack Kurulumu (Helm)

Prometheus, Grafana, Alertmanager ve Kubernetes node exporter gibi temel gözlemlenebilirlik bileşenlerini tek komutla kurmak için:

```bash
# 1. Prometheus topluluk deposunu ekleyin
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Üretim ortamına uygun depolama alanı (Longhorn/PVC) ile kurulum yapın
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="SecureGrafanaPass2026!" \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi
```

---

## 3. Loki ile Log Yönetimi ve LogQL

Loki, sunuculardan ve podlardan logları toplamak için **Promtail** veya **Grafana Alloy** ajanlarını kullanır.

```bash
# Helm ile Loki ve Promtail kurulumu:
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set grafana.enabled=false # Zaten kube-prometheus-stack içinde kurulu olduğu için kapatıyoruz
```

### LogQL (Loki Sorgu Dili) Örnekleri

Grafana Explore ekranında kullanabileceğiniz pratik sorgular:

```logql
# 1. production namespace'indeki web-app podlarında "ERROR" geçen satırları bulun ve json formatında filtreleyin:
{namespace="production", app="web-app"} |= "ERROR" | json | line_format "{{.message}}"

# 2. Son 5 dakikada uygulamalarda saniyede üretilen HTTP 500 hata oranlarını grafik olarak görün:
sum(rate({namespace="production"} |= "500" [5m])) by (app)
```

---

## 4. Alertmanager ile Akıllı Uyarılar (Alerting)

Metriklerde veya loglarda bir sapma algılandığında Alertmanager, Slack, PagerDuty veya Microsoft Teams üzerinden ekibe bildirim gönderir.

### Slack Bildirimi Yönlendirme YAML Örneği

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [lgtm_yigini_manifest_1.yaml](../Manifests/08_observability/lgtm_yigini_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Grafana Dashboard Yapılandırması

Grafana arayüzüne yerel makinenizden erişmek için port-forward yapabilirsiniz:

```bash
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
```

Tarayıcınızdan `http://localhost:3000` adresine gidin. Kullanıcı adı `admin` ve şifre kurulumda belirlediğiniz `SecureGrafanaPass2026!` olacaktır.

### Hazır ve Popüler Grafana Dashboard Kimlikleri (IDs)

Grafana arayüzünde "Import" seçeneğine aşağıdaki ID'leri yazarak hazır kurumsal panelleri saniyeler içinde yükleyebilirsiniz:

* `15757` ──► **Kubernetes Cluster Overview:** Genel küme durumu, CPU/RAM kullanımı ve Pod sayıları.
* `13659` ──► **Loki Log Dashboard:** Loki log sorgularını görselleştirme.
* `15172` ──► **Node Exporter Full:** Fiziksel sunucuların disk, CPU, RAM ve I/O grafikleri.
* `16611` ──► **Cilium/Hubble Dashboard:** eBPF tabanlı ağ trafiği izleme paneli.

---

## 6. SRE Altın Sinyalleri (The Four Golden Signals)

Google Site Reliability Engineering (SRE) standartlarına göre bir sistemi gözlemlerken mutlaka takip edilmesi gereken 4 ana metrik:

| Sinyal | Açıklama | PromQL Matematiksel İfadesi |
|:---|:---|:---|
| **Latency (Gecikme)** | İsteklerin yanıtlanma süresi (99. yüzdelik dilim) | `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))` |
| **Traffic (Trafik)** | Sisteme gelen saniyedeki istek sayısı | `sum(rate(http_requests_total[5m]))` |
| **Errors (Hatalar)** | Gelen isteklerin hata (5xx) oranı | `sum(rate(http_requests_total{code=~"5.."}[5m]))` |
| **Saturation (Doluluk)** | Kaynakların (CPU/RAM) sınıra ne kadar yaklaştığı | `sum(container_memory_usage_bytes) by (pod) / sum(container_spec_memory_limit_bytes) by (pod)` |
