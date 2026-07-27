# Prometheus Derinlemesine İnceleme (Prometheus Deep Dive)

**Prometheus**, bulut yerli (cloud-native) ve Kubernetes ekosisteminin fiili (de facto) standart metrik toplama, depolama ve uyarı (alerting) sistemidir. Çekme tabanlı (pull-based) mimarisi, güçlü sorgulama dili (**PromQL**) ve zaman serisi veritabanı (TSDB) yapısıyla 2026 yılında da izleme altyapılarının merkezinde yer almaktadır.

---

## 1. Prometheus Mimarisi

Prometheus, metriklerin kendisine gönderilmesini (push) beklemek yerine, kendisi hedef pod ve sunucuların `/metrics` endpoint'lerini periyodik olarak sorgulayarak (pull) verileri çeker.

```
┌─────────────────────────────────┐
│       Kubernetes Pod'ları       │  <--- /metrics (HTTP / Plain Text)
└────────────────┬────────────────┘
                 │
                 ▲ (Pull/Scrape)
┌────────────────┴────────────────┐
│        Prometheus Server        │
│  - TSDB (Time-Series Veritabanı)│ ──► [ Alertmanager ] ──► Slack / Teams
│  - PromQL Motoru                │ ──► [ Grafana ]      ──► Dashboard
└─────────────────────────────────┘
```

---

## 2. Kube-Prometheus-Stack Bileşenleri

Kümeyi izlemek için tüm exporter ve arayüzleri içeren yerleşik yığının (kube-prometheus-stack) kurulum komutu:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="SecurePass2026!" \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi
```

### Kurulan Temel Podlar

* `prometheus-kube-prometheus-operator`: CRD nesnelerini dinleyip konfigurasyonları güncelleyen operatör.
* `prometheus-kube-state-metrics`: Kubernetes API nesnelerinin (deployment, pod sayısı vb.) durum metriklerini üreten bileşen.
* `prometheus-prometheus-node-exporter`: Fiziksel sunucunun (RAM, CPU, Disk) donanım metriklerini toplayan DaemonSet.

---

## 3. ServiceMonitor ve PodMonitor Entegrasyonu

Prometheus Operator, scrape ayarlarını otomatik yönetmek için **ServiceMonitor** ve **PodMonitor** kaynaklarını kullanır.

* **ServiceMonitor:** Bir Kubernetes Servisi (Service) arkasındaki podları izlemek için etiket eşleştirmesi yapar.
* **PodMonitor:** Önünde bir servis bulunmayan, bağımsız veya DaemonSet podlardan doğrudan metrik toplar.

*(Detaylı kurulum şablonları için bkz: [prometheus_operator.md](prometheus_operator.md))*

---

## 4. PromQL (Prometheus Sorgu Dili)

PromQL, zaman serisi verilerini anlık veya zaman aralıklı sorgulamak için kullanılan güçlü bir dildir.

### Temel Veri Tipleri

1. **Instant Vector (Anlık Vektör):** Zamandaki tek bir an için üretilen değer.

    *Örn:* `container_memory_usage_bytes` (Şu andaki bellek tüketimi).

2. **Range Vector (Aralık Vektörü):** Zaman içindeki bir aralığı kapsayan veri kümesi.

    *Örn:* `container_memory_usage_bytes[5m]` (Son 5 dakikalık bellek değişim serisi).

### Sayaçlar (Counters) ve Değişim Oranları

Sayaçlar sadece artan metriklerdir (Örn: Toplam istek sayısı). Bunların saniyelik artış hızını hesaplamak için `rate()` fonksiyonu kullanılır:

```promql
# Son 5 dakikada saniye başına gelen ortalama HTTP isteği sayısı:
rate(http_requests_total[5m])
```

---

## 5. Kritik Kubernetes PromQL Sorguları

### Pod ve Konteyner İzleme

```promql
# 1. Konteyner bazlı CPU tüketimi (Core bazında):
rate(container_cpu_usage_seconds_total{container!=""}[5m])

# 2. Konteyner Bellek Tüketim Yüzdesi (Kullanılan RAM / Limit RAM):
container_memory_usage_bytes / container_spec_memory_limit_bytes

# 3. Son 1 Saatte 3'ten Fazla Restart Atan (CrashLoopBackOff) Podlar:
increase(kube_pod_container_status_restarts_total[1h]) > 3
```

### Sunucu (Node) İzleme

```promql
# 4. Sunucu CPU Kullanım Yüzdesi:
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (node)

# 5. Sunucu RAM Kullanım Yüzdesi:
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# 6. Sunucu Disk Doluluk Yüzdesi (Mount edilen disk alanı):
1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})
```

### Altyapı (etcd & API Server) İzleme

```promql
# 7. etcd Disk Diske Yazma Gecikmesi (99. yüzdelik - milisaniye cinsinden):
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) * 1000

# 8. API Server HTTP İstek Gecikmesi:
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m]))

# 9. API Server HTTP 5xx Hata Yüzdesi:
rate(apiserver_request_total{code=~"5.."}[5m]) / rate(apiserver_request_total[5m])
```

---

## 6. Recording Rules (Kayıt Kuralları) ile Performans Optimizasyonu

Çok büyük kümelerde, Grafana panellerinde her saniye çalışan ağır PromQL sorguları (örneğin 1 aylık rate hesaplamaları) Prometheus'un kilitlenmesine yol açabilir. Bu durumu engellemek için **Recording Rules** ile ağır sorgular arka planda periyodik olarak hesaplanıp yeni bir metrik olarak diske yazılır.

### Örnek Recording Rule Yapılandırması

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [prometheus_derinlemesine_inceleme_manifest_1.yaml](../Manifests/08_observability/prometheus_derinlemesine_inceleme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. Prometheus Federation ve Ölçekleme (Multi-Cluster)

Çok büyük altyapılarda veya yüzlerce kümenin (multi-cluster) olduğu sistemlerde tek bir Prometheus sunucusu dikey limitlere ulaşır. Bu sorunu çözmek için iki yöntem kullanılır:

1. **Prometheus Federation (Hiyerarşik Yapı):** Üst seviyedeki bir ana Prometheus sunucusu (Global Prometheus), alt kümelerde çalışan local Prometheus sunucularındaki önceden filtrelenmiş metrikleri çeker.
2. **Grafana Mimir / Thanos Entegrasyonu (Önerilen - 2026):** Local Prometheus sunucuları veriyi kendi disklerinde saklamak yerine, **Remote Write** protokolüyle merkezi ve nesne depolama (Object Storage - S3) tabanlı çalışan Grafana Mimir veya Thanos yığınlarına gönderirler. Bu sayede sonsuz metrik saklama kapasitesi elde edilir.

---

## 8. Yönetim ve Hata Ayıklama (Hot Reload)

Aşağıdaki komutlar, Prometheus yönetimi ve sorun giderme aşamalarında kullanılır:

```bash
# 1. Prometheus arayüzüne yerel erişim sağlama
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090

# 2. Config dosyalarında yapılan değişiklikleri yeniden başlatmadan yükleme (Hot Reload)
# Not: API Server üzerinde '--web.enable-lifecycle' parametresi açık olmalıdır.
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload

# 3. Aktif tarama hedeflerinin sağlık durumunu CLI üzerinden sorgulama
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```
