# DNS & CoreDNS Deep Dive

Kubernetes'teki tüm servis keşfi (service discovery) DNS üzerine kuruludur. CoreDNS, K8s 1.13'ten itibaren kube-dns'in yerini almış tek otorite DNS sunucusudur.

---

## CoreDNS Nasıl Çalışır?

```
[Pod]
  │  nslookup my-service.production.svc.cluster.local
  ▼
[CoreDNS Pod — kube-system namespace]
  │
  ├── Cluster içi isim → API Server'dan çöz
  └── Dış isim (google.com) → Upstream DNS'e ilet (node'un /etc/resolv.conf)
```

Her pod'un `/etc/resolv.conf` dosyası otomatik ayarlanır:

```
nameserver 10.96.0.10      # CoreDNS ClusterIP
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

---

## DNS Kayıt Türleri

### Servis DNS Kayıtları

```
# ClusterIP Service
<servis>.<namespace>.svc.cluster.local → ClusterIP

# Headless Service (clusterIP: None)
<servis>.<namespace>.svc.cluster.local → Tüm pod IP'leri (A kayıtları)

# Headless Service pod DNS — StatefulSet için kritik
<pod-adı>.<servis>.<namespace>.svc.cluster.local → Tek pod IP'si

# ExternalName Service
<servis>.<namespace>.svc.cluster.local → CNAME → external-host.com
```

### Pod DNS Kayıtları

```
# Pod hostname (varsayılan — IP'nin tire versiyonu)
<pod-ip-tire-ile>.<namespace>.pod.cluster.local
# Örnek: 10-244-1-15.default.pod.cluster.local → 10.244.1.15

# Özel hostname (pod spec'te hostname + subdomain tanımlanmışsa)
<hostname>.<subdomain>.<namespace>.svc.cluster.local
```

---

## CoreDNS ConfigMap

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors                          # Hataları logla
        health {                        # /health endpoint
           lameduck 5s
        }
        ready                           # /ready endpoint
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure                # Pod DNS kayıtları
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153                # Prometheus metrikleri
        forward . /etc/resolv.conf {    # Upstream DNS
           max_concurrent 1000
        }
        cache 30                        # DNS cache TTL (saniye)
        loop                            # Sonsuz döngü tespiti
        reload                          # ConfigMap değişince otomatik reload
        loadbalance                     # Round-robin A kaydı dönüşü
    }
```

---

## Özel DNS Yapılandırmaları

### Stub Zone — Belirli Domain için Farklı DNS

```yaml
# company.internal domainini şirket DNS sunucusuna yönlendir
data:
  Corefile: |
    .:53 {
        errors
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
        }
        forward . 8.8.8.8 8.8.4.4
        cache 30
        reload
    }
    company.internal:53 {
        errors
        forward . 192.168.1.10 192.168.1.11    # Şirket DNS sunucuları
        cache 30
    }
```

### Rewrite — DNS Alias

```yaml
# Eski servis adını yeni adına yönlendir (migrasyon geçiş dönemi)
.:53 {
    rewrite name exact old-service.production.svc.cluster.local \
                        new-service.production.svc.cluster.local
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
    }
    forward . /etc/resolv.conf
}
```

### Hosts — Statik Kayıtlar

```yaml
data:
  Corefile: |
    .:53 {
        hosts /etc/coredns/customhosts {
            192.168.1.100 legacy-db.internal
            192.168.1.101 legacy-api.internal
            fallthrough
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
        }
        forward . /etc/resolv.conf
        cache 30
        reload
    }
  customhosts: |
    192.168.1.100 legacy-db.internal
    192.168.1.101 legacy-api.internal
```

---

## ndots ve DNS Arama Sırası

`ndots:5` ayarı kısa isimlerin nasıl çözümlendiğini belirler:

```
# "my-service" sorgulandığında (nokta sayısı < 5):
1. my-service.default.svc.cluster.local → Bulunamazsa
2. my-service.svc.cluster.local → Bulunamazsa
3. my-service.cluster.local → Bulunamazsa
4. my-service. (tam isim) → Son çare

# Gecikmeyi azaltmak için FQDN kullanın (sonunda nokta):
nslookup my-service.production.svc.cluster.local.
```

### Pod Bazında DNS Politikası

```yaml
spec:
  dnsPolicy: ClusterFirst       # Varsayılan: cluster DNS önce
  # dnsPolicy: None             # dnsConfig ile tamamen özelleştir
  dnsConfig:
    nameservers:
    - 8.8.8.8
    searches:
    - production.svc.cluster.local
    - svc.cluster.local
    options:
    - name: ndots
      value: "2"                # ndots'u düşür → daha az gereksiz sorgu
    - name: timeout
      value: "2"
    - name: single-request-reopen  # Linux TCP/UDP paralel sorgu fix
```

---

## CoreDNS Ölçeklendirme

Büyük cluster'larda CoreDNS darboğaz olabilir:

```bash
# Mevcut replica sayısı
kubectl get deployment coredns -n kube-system

# Manuel ölçeklendirme
kubectl scale deployment coredns -n kube-system --replicas=4

# HPA — metrics-server gereklidir
kubectl autoscale deployment coredns -n kube-system \
  --min=2 --max=8 --cpu-percent=70
```

### NodeLocal DNSCache

Her node'da local DNS cache çalıştır — CoreDNS yükünü %80 azaltır ve conntrack tablo baskısını ortadan kaldırır:

```
# Akış:
Pod → 169.254.20.10 (NodeLocal DNS — link-local IP)
         │ Cache'de varsa anında döner
         │ Yoksa CoreDNS'e iletir
         ▼
     CoreDNS (kube-system)
```

```bash
# NodeLocal DNSCache durumu
kubectl get daemonset node-local-dns -n kube-system

# Kurulum (kubeadm cluster)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
```

---

## CoreDNS Metrikleri (Prometheus)

```promql
# DNS sorgu gecikmesi (p99)
histogram_quantile(0.99, rate(coredns_dns_request_duration_seconds_bucket[5m]))

# Sorgu hata oranı (SERVFAIL)
rate(coredns_dns_responses_total{rcode="SERVFAIL"}[5m])

# Cache hit oranı
rate(coredns_cache_hits_total[5m]) / rate(coredns_dns_requests_total[5m])

# Upstream DNS gecikme
rate(coredns_forward_request_duration_seconds_sum[5m]) /
rate(coredns_forward_request_duration_seconds_count[5m])

# NXDOMAIN oranı (servis bulunamama)
rate(coredns_dns_responses_total{rcode="NXDOMAIN"}[5m])
```

---

## CoreDNS Yüksek Erişilebilirlik

```yaml
# CoreDNS Deployment — PodAntiAffinity ile farklı node'lara dağıt
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
spec:
  replicas: 3    # Minimum 2, prod için 3+
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                k8s-app: kube-dns
            topologyKey: kubernetes.io/hostname
      priorityClassName: system-cluster-critical
      containers:
      - name: coredns
        resources:
          requests:
            cpu: 100m
            memory: 70Mi
          limits:
            cpu: 200m
            memory: 300Mi    # OOMKill'e karşı yeterli limit
```

> [!TIP]
> DNS sorunlarını hızlı debug etmek için: `kubectl run dns-test --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --restart=Never -it --rm -- bash` ve içinde `nslookup`, `dig` araçlarını kullanın. `busybox` da çalışır ama `dig` içermez.
