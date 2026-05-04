# DNS Troubleshooting — CoreDNS Hata Ayıklama

Kubernetes'te en sık karşılaşılan ağ sorunlarının büyük bölümü DNS kaynaklıdır. Pod'lar servis isimlerini çözümleyemez, dış alan adlarına ulaşamaz veya beklenmedik sürelerle timeout alır.

> [!NOTE]
> Bu dosya yalnızca sorun giderme odaklıdır. CoreDNS mimarisi, ConfigMap yapılandırması, stub zone ve ölçeklendirme için `Networking/DNS & CoreDNS.md` dosyasına bakın.

---

## Hızlı Tanı

```bash
# CoreDNS pod'larının durumu
kubectl get pods -n kube-system -l k8s-app=kube-dns

# CoreDNS logları (canlı)
kubectl logs -n kube-system -l k8s-app=kube-dns -f

# CoreDNS yapılandırması
kubectl get configmap coredns -n kube-system -o yaml
```

---

## DNS Testi — Debug Pod

```bash
# Geçici DNS test pod'u başlat
kubectl run dns-test \
  --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --restart=Never \
  -it --rm \
  -- /bin/bash

# Pod içinde testler:
nslookup kubernetes.default           # Cluster-internal DNS
nslookup kubernetes.default.svc.cluster.local
nslookup google.com                   # Upstream DNS
dig @10.96.0.10 my-service.production.svc.cluster.local
```

```bash
# Belirli namespace'den test
kubectl run dns-test -n production \
  --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --restart=Never -it --rm \
  -- nslookup my-service
```

---

## Yaygın Sorunlar ve Çözümleri

### 1. `ndots: 5` — Yavaş DNS Çözümlemesi

**Sorun:** `ndots: 5` varsayılan ayarıyla, `google.com` gibi kısa isimler için önce 5 cluster.local suffix denenince gereksiz latency oluşur.

```
google.com → google.com.production.svc.cluster.local (NXDOMAIN)
           → google.com.svc.cluster.local (NXDOMAIN)
           → google.com.cluster.local (NXDOMAIN)
           → google.com. (başarılı — ama 3 gereksiz sorgu yapıldı)
```

**Çözüm:** Pod spec'inde `ndots` değerini düşür:

```yaml
spec:
  dnsConfig:
    options:
    - name: ndots
      value: "2"     # Sadece 2 noktadan az ise suffix dene
    - name: single-request-reopen
    - name: timeout
      value: "2"
  dnsPolicy: ClusterFirst
```

---

### 2. CoreDNS CrashLoopBackOff

```bash
kubectl describe pod -n kube-system <coredns-pod>
# Events: OOMKilled → Memory limit yetersiz

# CoreDNS memory limitini artır
kubectl edit deployment coredns -n kube-system
# resources.limits.memory: 170Mi → 300Mi
```

---

### 3. Upstream DNS Sorunu

```bash
# Corefile'daki upstream DNS sunucusu
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'

# forward . /etc/resolv.conf  ← host DNS'i kullanıyor
# forward . 8.8.8.8 8.8.4.4  ← Google DNS

# Node'un upstream DNS'i kontrol et
kubectl debug node/<node-adı> -it --image=ubuntu -- cat /etc/resolv.conf
```

**Özel upstream DNS yapılandırması:**

```yaml
# CoreDNS ConfigMap — belirli domainler için farklı DNS sunucusu
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 8.8.4.4 {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }

    # Şirket iç domain'i için özel DNS sunucusu
    company.internal:53 {
        errors
        cache 30
        forward . 10.0.0.53    # Şirket iç DNS
    }
```

---

### 4. NetworkPolicy DNS Engellemesi

NetworkPolicy UDP/53 portunu engelliyor olabilir:

```bash
# DNS trafiğinin drop olup olmadığını Hubble ile gör
hubble observe \
  --pod production/my-pod \
  --protocol UDP \
  --verdict DROPPED -f
```

```yaml
# DNS'e izin veren NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}    # tüm pod'lar
  policyTypes: [Egress]
  egress:
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
```

---

### 5. Service'in ClusterIP'si Yok (Headless)

```bash
kubectl get svc my-service -n production
# ClusterIP: None  → Headless service → nslookup farklı döner

# Headless service DNS davranışı:
# my-service.production.svc.cluster.local → Pod IP'leri (A records)
# my-service.production.svc.cluster.local → ClusterIP (normal service)
```

---

## CoreDNS Metrics (Prometheus)

```bash
# CoreDNS Prometheus endpoint'i
kubectl port-forward -n kube-system svc/kube-dns 9153:9153
curl http://localhost:9153/metrics | grep coredns_dns
```

**Önemli metrikler:**

| Metrik | Açıklama |
|:-------|:---------|
| `coredns_dns_requests_total` | Toplam sorgu sayısı |
| `coredns_dns_responses_total` | Yanıt kodu dağılımı (NOERROR, NXDOMAIN) |
| `coredns_forward_requests_total` | Upstream'e iletilen sorgular |
| `coredns_cache_hits_total` | Cache hit oranı |
| `coredns_dns_request_duration_seconds` | DNS yanıt süresi dağılımı |

```promql
# DNS hata oranı
sum(rate(coredns_dns_responses_total{rcode="SERVFAIL"}[5m]))
/
sum(rate(coredns_dns_responses_total[5m]))

# Ortalama DNS yanıt süresi
histogram_quantile(0.99,
  sum(rate(coredns_dns_request_duration_seconds_bucket[5m])) by (le)
) * 1000    # ms cinsinden
```

---

## Tanı Kontrol Listesi

```
□ kubectl get pods -n kube-system -l k8s-app=kube-dns  → Running?
□ CoreDNS loglarında hata var mı?
□ /etc/resolv.conf ndots değeri uygun mu?
□ NetworkPolicy UDP/53'e izin veriyor mu?
□ Upstream DNS sunucusu erişilebilir mi?
□ nslookup kubernetes.default çalışıyor mu?
□ Servis selector'ı pod label'larıyla eşleşiyor mu?
□ Endpoint'ler dolu mu? kubectl get endpoints <svc>
```

> [!TIP]
> DNS sorunlarını debug etmenin en hızlı yolu: `kubectl run dns-test --image=busybox:1.36 --restart=Never -it --rm -- nslookup <hedef>`. 30 saniyede sonuç alırsınız.
