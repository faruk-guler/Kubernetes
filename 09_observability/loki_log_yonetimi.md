# Grafana Loki ile Merkezi Günlük (Log) Yönetimi

**Grafana Loki**, bulut yerli (cloud-native) mimarilerde Kubernetes pod'larının loglarını toplamak, depolamak ve sorgulamak amacıyla geliştirilmiş yüksek ölçeklenebilir ve düşük maliyetli bir log birleştirme (log aggregation) sistemidir. Prometheus ile aynı felsefede tasarlanmış olan Loki; logların içeriğini indekslemek yerine, kaynak etiketlerini (labels) indeksleyerek kaynak tüketimini en aza indirir.

---

## 1. Loki Mimarisi ve Bileşenleri

Loki, mikroservis yapısında (distributed) veya tek bir pod olarak (monolithic) çalıştırılabilen modüler bir mimariye sahiptir:

```
[ Pod stdout / stderr ]
          │
          ▼
┌──────────────────┐
│ Promtail / Agent │ (DaemonSet - Her node'da çalışır, logları toplar ve etiketler)
└────────┬─────────┘
         │
         ▼ (HTTP / Protobuf)
┌─────────────────────────────────────────────────────────────┐
│                        Grafana Loki                         │
│  - Distributor : Gelen logları doğrular ve dağıtır.         │
│  - Ingester    : Log satırlarını bellekte birleştirir.      │
│  - Compactor   : Logları sıkıştırıp bloklar halinde yazar.   │
│  - Querier     : LogQL sorgularını işler.                   │
└────────┬────────────────────────────────────────────────────┘
         │
         ▼ (Nesne Depolama / Object Store)
┌─────────────────────────────────────────────────────────────┐
│              S3 / Google Cloud Storage / MinIO              │
└─────────────────────────────────────────────────────────────┘
```

* **Promtail:** Her işçi düğümünde (worker node) DaemonSet olarak çalışan ve pod loglarını Kubernetes API'sinden aldığı etiketlerle (namespace, pod, container) zenginleştirerek Loki'ye gönderen ajandır.
* **Ingester:** Gelen logları hemen diske yazmak yerine ram bellekte sıkıştırılmış bloklar (chunks) halinde tutar ve belirli aralıklarla kalıcı depolama alanına (Object Store) gönderir.
* **Querier:** Grafana üzerinden gelen LogQL sorgularını çözümler ve Ingester'daki aktif veriler ile Object Store'daki geçmiş verileri birleştirerek döndürür.

---

## 2. Kurulum ve S3/MinIO Depolama Yapılandırması

Loki'yi yüksek kullanılabilirlikte ve kalıcı bir nesne depolama (Object Storage) arkasında çalıştırmak için Helm konfigürasyonu (`loki-values.yaml`) şu şekilde kurgulanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [loki_log_yonetimi_manifest_2.yaml](../Manifests/08_observability/loki_log_yonetimi_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Kurulum komutu:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# S3 yapılandırmasıyla distributed kurulum
helm install loki grafana/loki-distributed \
  --namespace monitoring \
  -f loki-values.yaml
```

---

## 3. Promtail Yapılandırması

Promtail, sunuculardaki `/var/log/pods` dizinindeki log dosyalarını okur ve Kubernetes metadata bilgilerini loglara etiket olarak zımbalar.

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [loki_log_yonetimi_manifest_1.yaml](../Manifests/08_observability/loki_log_yonetimi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. LogQL (Log Query Language) Kullanımı

LogQL sorguları iki ana kısma ayrılır: **Stream Selectors** (akış seçiciler) ve **Filter Expressions** (filtre ifadeleri).

### A. Akış Seçiciler (Stream Selectors)

```logql
# production isim alanındaki api podunun loglarını seç
{namespace="production", app="api"}

# Düzenli ifade (regex) kullanarak staging veya production loglarını seç
{namespace=~"production|staging"}
```

### B. Filtre İfadeleri

```logql
# Metin içeren logları filtreleme
{app="api"} |= "ERROR"

# Metin hariç tutma (healthcheck loglarını gizle)
{app="api"} != "healthcheck"

# JSON formatındaki logları parse etme ve alan kısıtlama
{app="api"} | json | level="error" | status_code >= 500
```

### C. Metrik Üreten LogQL Sorguları

```logql
# Son 5 dakikada saniye başına düşen ERROR loglarının rate oranı:
rate({namespace="production"} |= "ERROR" [5m])

# JSON formatındaki loglardan P99 istek süresini (response time) hesaplama:
quantile_over_time(0.99, {app="api"} | json | unwrap duration_ms [5m]) by (endpoint)
```

---

## 5. Kardinalite Riski ve Doğru Etiket Stratejisi

Loki'de yapılan en büyük hata, her benzersiz değer için bir etiket (label) tanımlamaktır. Buna **yüksek kardinalite** (high cardinality) denir ve Loki'nin çökmesine yol açar.

* ❌ **YASAK - Yüksek Kardinalite Etiketleri:** `user_id`, `request_id`, `ip_address`, `email`. (Her istekte değişen değerler asla label yapılmamalıdır!)
* ✅ **DOĞRU - Düşük Kardinalite Etiketleri:** `namespace`, `app`, `container`, `env`, `level`. (Değişken sayısı çok az olan etiketler).
* **Çözüm:** Yüksek kardinaliteli verileri log satırı içinde tutun ve sorgu anında LogQL filtreleri (`| json | user_id="1234"`) ile ayıklayın.

---

## 6. Loki ve Prometheus Metrik Korelasyonu (Derived Fields)

Grafana üzerinde Prometheus metrik grafiğindeki bir sapmayı incelerken, tek tıkla o andaki Loki loglarına atlamak için **Derived Fields (Türetilmiş Alanlar)** kullanılır.

Grafana veri kaynağı (Data Source) ayarlarında tanımlanan kural ile, log satırındaki `trace_id` veya `request_id` yakalanarak doğrudan dağıtık izleme aracı Tempo'ya veya Loki loglarına link verilebilir:

```json
# Grafana Loki Veri Kaynağı Yapılandırması (JSON)
{
  "derivedFields": [
    {
      "name": "TraceID",
      "matcherRegex": "trace_id=(\\w+)",
      "url": "http://localhost:3000/explore?left=%5B%22now-1h%22,%22now%22,%22Tempo%22,%7B%22query%22:%22${__value.raw}%22%7D%5D"
    }
  ]
}
```

---

## 7. LogQL Alert Rules (Log Tabanlı Uyarı Kuralları)

Sisteminizde belirli bir log türü (örneğin veritabanı bağlantı hatası) çok sık çıktığında otomatik uyarı tetiklemek için `PrometheusRule` içine LogQL sorguları yazabilirsiniz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [loki_log_yonetimi_manifest_3.yaml](../Manifests/08_observability/loki_log_yonetimi_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 8. Yönetim ve Hata Ayıklama (Troubleshooting)

```bash
# 1. Loki bileşeninin hazır (Ready) olup olmadığını kontrol etme
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/ready

# 2. Distributor bileşeninin saniyede aldığı log boyutunu (metrik cinsinden) sorgulama
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/metrics | grep loki_distributor_bytes_received

# 3. Promtail toplayıcısının log dosyasını izleyerek hata analizi yapma
kubectl logs -n monitoring -l app=promtail -f --tail=20
```
