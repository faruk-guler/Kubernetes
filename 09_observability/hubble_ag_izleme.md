# Cilium Hubble ile Ağ Gözlemlenebilirliği (Network Observability)

Cilium CNI, eBPF teknolojisini kullandığı için kümedeki tüm ağ trafiğini işletim sistemi çekirdeği düzeyinde en ince ayrıntısına kadar gözlemleyebilir. **Hubble**, Cilium'un topladığı bu ağ verilerini anlamlı grafiklere, servis haritalarına ve gerçek zamanlı sorgulanabilir ağ günlüklerine (flow logs) dönüştürür. Üstelik bunu podların içine sidecar enjekte etmeden veya uygulama koduna dokunmadan gerçekleştirir.

---

## 1. Hubble Nedir?

Hubble, geleneksel ağ izleme araçlarından farklı olarak çekirdek (kernel) seviyesinde paket yakalar:

```
Geleneksel Ağ İzleme:
  Uygulama Podu ──► Ajan (DaemonSet) ──► Paket Yakalama (tcpdump) ──► Yüksek Performans Kaybı

Hubble eBPF İzleme:
  Kernel Hooks (Cilium eBPF) ──► Paket Filtreleme (Overhead Yok) ──► Hubble Relay ──► CLI / UI
```

Hubble üç katmanlı bir yapıda çalışır:

1. **Veri Toplama (Cilium Agent):** Her node üzerinde DaemonSet olarak çalışır, eBPF kancaları yardımıyla paketi çekirdekten doğrudan okur.
2. **Birleştirme (Hubble Relay):** Tüm düğümlerden gelen yerel akış (flow) verilerini tek bir merkezde birleştirir.
3. **Görselleştirme (Hubble UI ve CLI):** Kullanıcının gerçek zamanlı sorgular atabileceği komut satırı ve görsel servis haritası arayüzü sunar.

---

## 2. Hubble ve CLI Kurulumu

Hubble'ı mevcut Cilium kurulumunuz üzerinde aktif etmek ve CLI aracını yüklemek için:

```bash
# 1. Helm ile Cilium üzerinde Hubble bileşenlerini etkinleştirin
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2}"

# 2. Hubble CLI Kurulumu (Linux)
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --fail --remote-name-all \
  https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz
tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin
rm hubble-linux-amd64.tar.gz

# 3. Port Yönlendirmeyi başlatarak kurulumu doğrulayın
cilium hubble port-forward &
hubble status
hubble observe --last 10
```

---

## 3. Hubble CLI ile Ağ Trafiği Analizi

Hubble CLI (`hubble observe`), terminal üzerinden gerçek zamanlı ağ trafiğini izlemek ve sorunları gidermek için tasarlanmış mükemmel bir araçtır.

```bash
# 1. Belirli bir podun ağ trafiğini canlı (stream) olarak izleyin:
hubble observe --pod production/my-app-pod -f

# 2. NetworkPolicy kuralları tarafından engellenen (DROPPED) paketleri yakalayın:
hubble observe --verdict DROPPED -f

# 3. İki pod arasındaki iletişimi canlı gözlemleyin:
hubble observe --from-pod production/frontend --to-pod production/backend -f

# 4. Kümedeki DNS sorgularını ve çözümlenemeyen adresleri izleyin:
hubble observe --protocol dns -f

# 5. Log toplama ve SIEM analizleri için JSON çıktısı üretip jq ile filtreleyin:
hubble observe --output json | \
  jq '.flow | {
    time: .time,
    src: .source.pod_name,
    dst: .destination.pod_name,
    verdict: .verdict,
    l4: .l4,
    http: .l7.http
  }'
```

### Geçmişe Yönelik Ağ Akış Sorguları

```bash
# 1. production namespace'indeki veritabanı (port 5432) trafiğini inceleme:
hubble observe --to-port 5432 --namespace production

# 2. Belirli bir zaman aralığındaki ağ akışlarını listeleme:
hubble observe \
  --since 2026-07-11T10:00:00 \
  --until 2026-07-11T10:05:00 \
  --namespace production
```

---

## 4. Hubble UI (Grafiksel Servis Haritası)

Hubble UI, mikroservislerin birbirleriyle nasıl konuştuğunu gösteren dinamik bir ağ topolojisi (Service Map) sunar:

```bash
# Hubble UI arayüzünü otomatik tarayıcıda açma:
cilium hubble ui

# Veya manuel port-forward ile erişim:
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Tarayıcıdan http://localhost:12000 adresine gidin
```

### UI Üzerinde Neler Görebilirsiniz?

* **Service Map:** Hangi podun hangi servise bağlandığını ve hangi protokolü (HTTP, TCP, gRPC) kullandığını canlı grafiksel haritada gösterir.
* **Ağ Filtreleme:** Sadece belirli bir isim alanındaki trafiği göster veya drop olanları kırmızı (`DROPPED`), kabul edilenleri yeşil (`FORWARDED`) olarak renklendir.

---

## 5. Hubble Prometheus Metrikleri

Hubble'ın ürettiği ağ metriklerini Prometheus ile toplayıp Grafana üzerinde görselleştirebilirsiniz:

| Metrik | Açıklama |
|:---|:---|
| `hubble_drop_total` | Ağ politikaları (NetworkPolicy) nedeniyle engellenen paketlerin sayısı. |
| `hubble_flows_processed_total` | İşlenen toplam ağ akışı (verdict bazında filtrelenebilir). |
| `hubble_dns_queries_total` | DNS sorguları ve yanıt kodları (Örn: NXDOMAIN). |
| `hubble_http_requests_total` | HTTP istek sayıları ve durum kodları (2xx, 5xx vb.). |

### Örnek PromQL Ağ Alarmları

```promql
# 1. Kümedeki anlık paket drop (engellenme) hızı:
rate(hubble_drop_total[5m])

# 2. Küme genelinde HTTP 5xx hata yüzdesi:
sum(rate(hubble_http_requests_total{status=~"5.."}[5m])) / sum(rate(hubble_http_requests_total[5m]))
```

> [!TIP]
> Grafana'ya Hubble metriklerini aktarmak için **16611** numaralı resmi Grafana Dashboard ID'sini kullanabilirsiniz.

---

## 6. Gerçek Dünya Ağ Hata Çözümü (Debugging)

### Senaryo 1: Frontend podu Backend poduna neden bağlanamıyor (Timeout)?

```bash
# Canlı akışı izleyip engellenen paketi bulun:
hubble observe \
  --from-pod production/frontend \
  --to-pod production/backend \
  --output json -f | jq 'select(.flow.verdict == "DROPPED")'

# Yanıt Raporu: "Verdict: DROPPED, Reason: NetworkPolicy ingress denied."
# Çözüm: Backend poduna ait NetworkPolicy dosyasına frontend podundan 80 portuna erişim izni (ingress rule) ekleyin.
```

### Senaryo 2: Kümede şüpheli dış bağlantı (Data Exfiltration) var mı?

```bash
# production namespace'inden küme dışındaki (Internet) IP'lere giden bağlantıları bulun:
hubble observe \
  --namespace production \
  --type l3-l4 -f | \
  jq 'select(.flow.destination.namespace == "") | {src: .flow.source.pod_name, dst_ip: .flow.IP.destination}'
```
