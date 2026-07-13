# API Priority and Fairness ile API Sunucu Güvenliği (API Priority & Fairness)

Büyük ve yoğun Kubernetes kümelerinde (clusters) API Server bazen aşırı yüklenebilir. Örneğin, hatalı yazılmış üçüncü parti bir denetleyici (controller) saniyede binlerce kontrol isteği göndererek API Server'ın tüm kaynaklarını tüketebilir. Bu durum, sistemin geri kalanında podların yönetilememesine ve yöneticilerin `kubectl` komutları çalıştıramamasına yol açar.

**API Priority and Fairness (APF)**, Kubernetes API Server'a gelen istekleri türlerine göre sınıflandıran, önceliklendiren ve adil bir şekilde kuyruğa alarak (fair queuing) kümenin tamamen kilitlenmesini engelleyen yerleşik bir koruma mekanizmasıdır.

---

## 1. APF Neden Gerekli? (Eski vs. Yeni Mekanizma)

* **Eski Mekanizma (`maxRequestsInFlight`):**

  Eşzamanlı maksimum okuma ve yazma istekleri için sabit iki üst limit tanımlanırdı. Bu limitler aşıldığında API Server `429 Too Many Requests` hatası fırlatırdı. Ancak bu filtreleme rastgele yapıldığından, kritik sistem podlarının (kubelet, scheduler) can simidi istekleri de bloke edilir ve küme çöküşe sürüklenirdi.

* **Yeni Mekanizma (APF):**

  Her istek türü kendi kulvarına (FlowSchema) atanır. Kulvarlar belirli öncelik seviyelerine (PriorityLevel) bağlanarak adil bir kaynak dağıtımı (Fair Queuing) ile işlenir. Hatalı çalışan bir servis sadece kendi kulvarını tıkar; sistemin geri kalanı (master/system istekleri) kesintisiz çalışmaya devam eder.

---

## 2. APF Temel Yapıtaşları

İsteklerin önceliklendirilmesi iki temel nesne üzerinden yönetilir:

```
[ Gelen API İsteği ]
         │
         ▼
 1. [ FlowSchema ] ──► İsteğin tipine göre (Kullanıcı, Namespace, ServiceAccount) eşleşme yapar.
         │
         ▼
 2. [ PriorityLevelConfiguration ] ──► İsteğin kaç adet eşzamanlı çalışma hakkı (Concurrency Shares)
                                      ve ne kadar kuyruk kapasitesi alacağını belirler.
```

---

## 3. Varsayılan Hazır Şablonlar (FlowSchemas & PriorityLevels)

Kubernetes kurulduğunda sisteminizi korumak için hazır kurallar otomatik olarak oluşturulur:

```bash
# 1. Mevcut FlowSchema listesini inceleyin
kubectl get flowschemas
# Önemli Şablonlar:
# - exempt: Sistem yöneticisi (masters) ve sağlık kontrolleri (/healthz) asla bloke edilmez.
# - system-nodes: Kubelet'lerin gönderdiği kalp atışı (heartbeat) istekleri.
# - service-accounts: Küme içindeki normal uygulamaların istekleri.

# 2. Öncelik seviyelerini (PriorityLevelConfiguration) listeleyin
kubectl get prioritylevelconfigurations
# exempt (sınırsız), workload-high, workload-low, global-default gibi seviyeler mevcuttur.
```

---

## 4. PriorityLevelConfiguration ve FlowSchema Yapılandırması

Kendi özel uygulamalarınız için öncelik kuralı tanımlamak isterseniz şu iki YAML dosyasını kurgulayabilirsiniz:

### Adım 1: PriorityLevelConfiguration Tanımı

Bu tanım, kuyruk yapısını ve ayrılan kaynak miktarını belirler:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [api_onceliklendirme_ve_adalet_manifest_1.yaml](../Manifests/04_infrastructure/api_onceliklendirme_ve_adalet_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Adım 2: FlowSchema Tanımı

Bu tanım, belirli bir namespace altındaki istekleri yukarıdaki öncelik seviyesine bağlar:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [api_onceliklendirme_ve_adalet_manifest_2.yaml](../Manifests/04_infrastructure/api_onceliklendirme_ve_adalet_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. APF Durum İzleme ve Tanılama (Debugging)

API sunucunuzda hangi isteklerin kuyrukta beklediğini veya reddedildiğini izlemek için şu tanı yöntemlerini kullanabilirsiniz:

```bash
# 1. API Server'daki güncel FlowControl durumunu JSON formatında dökün
kubectl get --raw /debug/api/v1/flowcontrol/dump | python3 -m json.tool

# 2. Prometheus metriklerinden reddedilen istek sayılarını çekin
kubectl get --raw /metrics | grep apiserver_flowcontrol_rejected_requests_total

# 3. Canlı sistemde 429 veya kuyruk sınırı hatası alan olayları arayın
kubectl get events -A | grep -i "too many requests"
```

### Prometheus PromQL Analiz Sorguları

```promql
# Saniye başına reddedilen istek hızı (0'dan büyükse dar boğaz vardır)
rate(apiserver_flowcontrol_rejected_requests_total[5m])

# Kuyrukta bekleyen isteklerin p99 bekleme süreleri
histogram_quantile(0.99, rate(apiserver_flowcontrol_request_wait_duration_seconds_bucket[5m]))
```

---

## Özet

API Priority and Fairness (APF), Kubernetes API Server'ın yoğun yükler altında dahi sistem kararlılığını korumasını sağlayan en kritik güvenlik duvarıdır. Kritik sistem isteklerine (**exempt**, **system-nodes**) sınırsız hak tanırken, normal kullanıcı ve servis hesaplarını adil kuyruk mekanizmalarıyla sınırlandırarak tekil servis arızalarının tüm kümenin çökmesine yol açmasını engeller.
