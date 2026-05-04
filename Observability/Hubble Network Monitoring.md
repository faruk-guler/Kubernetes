# Cilium Hubble ile Ağ Gözlemlenebilirliği

Cilium eBPF kullandığı için ağ trafiğini en ince ayrıntısına kadar görebilir. **Hubble**, bu verileri görselleştirir ve sorgulanabilir hale getirir. Herhangi bir sidecar, agent veya kod değişikliği gerektirmez.

---

## Hubble Nedir?

```
Geleneksel izleme:  Uygulama → log yaz → collector → görselleştir
Hubble:             Kernel (eBPF hook) → her paket yakalanır → anında görselleştir
```

Hubble üç katmanda çalışır:

| Katman | Bileşen | Görev |
|:-------|:--------|:------|
| **Veri toplama** | Cilium agent (DaemonSet) | eBPF ile her paketi yakalar |
| **Aggregation** | Hubble Relay | Tüm node'lardan veriyi birleştirir |
| **Görselleştirme** | Hubble UI + CLI | Gerçek zamanlı sorgu ve harita |

---

## Kurulum

```bash
# Cilium kuruluysa Hubble'ı etkinleştir (helm ile)
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2}"

# Veya cilium CLI ile
cilium hubble enable --ui

# Hubble CLI kurulumu
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --fail --remote-name-all \
  https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz
tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin
rm hubble-linux-amd64.tar.gz

# Kurulumu doğrula
cilium hubble port-forward &
hubble status
hubble observe --last 10
```

---

## Ağ Trafiği İzleme

```bash
# Belirli bir pod'un tüm trafiğini canlı izle
hubble observe --pod production/my-app-pod -f

# HTTP trafiğini filtrele (method, URL, response code dahil)
hubble observe --protocol http --output flow -f

# Drop edilen paketleri gör (NetworkPolicy ihlalleri)
hubble observe --verdict DROPPED -f

# Belirli kaynak → hedef yolu
hubble observe \
  --from-pod production/frontend \
  --to-pod production/backend \
  -f

# Sadece belirli namespace
hubble observe --namespace production --verdict DROPPED -f

# DNS sorgularını izle
hubble observe --protocol dns -f

# JSON formatında çıktı (SIEM/log pipeline entegrasyonu için)
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

### Geçmişe Dönük Sorgular

```bash
# Son 100 akış (retry/timeout analizi için)
hubble observe --last 100 --pod production/api

# Zaman aralığı ile
hubble observe \
  --since 2026-05-04T10:00:00 \
  --until 2026-05-04T10:05:00 \
  --namespace production

# Belirli port'a gelen trafik
hubble observe --to-port 5432 --namespace production -f
```

---

## Hubble UI — Service Map

```bash
# Port yönlendirme ile UI'ya eriş
cilium hubble ui    # Otomatik browser açar

# Manuel port-forward
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# http://localhost:12000
```

Hubble UI'da görebilecekleriniz:
- **Service Map**: pod'lar arası gerçek zamanlı trafik grafiği
- **Namespace filtresi**: sadece ilgili namespace'i göster
- **Verdict renklendirmesi**: yeşil (FORWARDED) / kırmızı (DROPPED)
- **Flow inceleme**: tek tıkla L3/L4/L7 detayları

---

## Hubble ile Güvenlik Denetimi

NetworkPolicy kurallarının doğru çalışıp çalışmadığını doğrulama:

```bash
# Hangi bağlantılar policy tarafından engelleniyor?
hubble observe --verdict DROPPED --namespace production -f

# Belirli bir label'dan database'e giden ve drop olan trafik
hubble observe \
  --from-label app=frontend \
  --to-label app=database \
  --verdict DROPPED

# Dış dünyaya (egress) yetkisiz çıkış girişimleri
hubble observe \
  --namespace production \
  --verdict DROPPED \
  --type l3-l4 -f | grep -v "kube-system"

# DNS başarısızlıkları (NXDOMAIN)
hubble observe \
  --protocol dns \
  --namespace production -f | grep NXDOMAIN
```

---

## Prometheus Metrikleri

```bash
# Hubble metric endpoint
kubectl port-forward -n kube-system svc/hubble-relay 4244:4244
```

**Önemli Hubble metrikleri:**

| Metrik | Açıklama |
|:-------|:---------|
| `hubble_drop_total` | NetworkPolicy tarafından drop edilen paket sayısı |
| `hubble_flows_processed_total` | İşlenen toplam akış (label: type, verdict) |
| `hubble_dns_queries_total` | DNS sorgu sayısı (label: rcode) |
| `hubble_tcp_flags_total` | TCP flag dağılımı (SYN, FIN, RST) |
| `hubble_http_requests_total` | HTTP istek sayısı (label: method, status) |
| `hubble_http_request_duration_seconds` | HTTP yanıt süresi histogram |

```promql
# Drop oranı (NetworkPolicy etkinliği)
rate(hubble_drop_total[5m])

# HTTP 5xx oranı
sum(rate(hubble_http_requests_total{status=~"5.."}[5m]))
/
sum(rate(hubble_http_requests_total[5m]))

# DNS başarısızlık oranı
rate(hubble_dns_queries_total{rcode="NXDOMAIN"}[5m])
/
rate(hubble_dns_queries_total[5m])
```

### Grafana Dashboard

Cilium/Hubble resmi dashboard ID: **16611**

```bash
# Grafana'ya import
curl -s https://grafana.com/api/dashboards/16611/revisions/latest/download | \
  jq .json > hubble-dashboard.json
```

---

## Gerçek Dünya Kullanım Senaryoları

### Senaryo 1: Neden Timeout Alıyorum?

```bash
# frontend → backend timeout debug
hubble observe \
  --from-pod production/frontend \
  --to-pod production/backend \
  --output json -f | jq '. | select(.flow.verdict == "DROPPED")'

# Cevap: NetworkPolicy 8080 portunu bloke ediyor
# Çözüm: NetworkPolicy'ye 8080 TCP egress ekle
```

### Senaryo 2: Hangi Pod Dış IP'ye Gidiyor?

```bash
# Beklenmedik dış bağlantılar (data exfiltration şüphesi)
hubble observe \
  --namespace production \
  --type l3-l4 -f | \
  jq '. | select(.flow.destination.namespace == "") | {src: .flow.source.pod_name, dst_ip: .flow.IP.destination}'
```

### Senaryo 3: Database Bağlantı Problemi

```bash
# production → database namespace arası trafik
hubble observe \
  --from-namespace production \
  --to-namespace database \
  --verdict DROPPED -f

# Tüm PostgreSQL (5432) trafiği
hubble observe --to-port 5432 --namespace production
```

> [!TIP]
> Hubble, "neden timeout alıyorum?" türündeki ağ sorunlarını çözmede `ssh + tcpdump` kombinasyonundan 10 kat daha hızlıdır. NetworkPolicy drop'larını, DNS başarısızlıklarını ve yavaş bağlantıları anlık görürsünüz — pod'a exec bile girmenize gerek kalmaz.
