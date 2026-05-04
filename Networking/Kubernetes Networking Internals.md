# Kubernetes Networking Internals

"Neden pod'lar birbirini buluyor?", "Paket gerçekte nasıl gidiyor?", "kube-proxy ne yapıyor?" sorularının cevabı burada. Bu bilgi olmadan ağ sorunlarını kör olarak çözmek zorunda kalırsın.

---

## Temel Kural: Her Pod Benzersiz IP Alır


```
Node 1 (192.168.1.10):
  Pod A: 10.244.1.2
  Pod B: 10.244.1.3

Node 2 (192.168.1.11):
  Pod C: 10.244.2.2
  Pod D: 10.244.2.3

Kural: Pod A → Pod C doğrudan iletişim kurabilir (NAT yok)
       10.244.1.2 → 10.244.2.2 — Her iki IP de erişilebilir
```

Bu kural **CNI (Container Network Interface)** tarafından sağlanır.

---

## Paket Yolculuğu: Pod → Pod (Aynı Node)

```
Pod A (10.244.1.2) → Pod B (10.244.1.3)

1. Pod A → veth pair → Host bridge (cbr0 veya cni0)
2. Bridge → Pod B'nin veth pair → Pod B

# Linux bridge gör
ip link show type bridge
ip link show type veth
```

---

## Paket Yolculuğu: Pod → Pod (Farklı Node)

```
Pod A (10.244.1.2) @ Node1 → Pod C (10.244.2.2) @ Node2

kube-proxy (iptables modu):
1. Pod A → veth → bridge
2. Bridge → iptables → Route table
3. Route: 10.244.2.0/24 → via 192.168.1.11 (Node2 IP)
4. Paket Node2'ye gider (UDP/GRE tunnel veya native routing)
5. Node2 bridge → Pod C veth → Pod C

# Route tablosuna bak (node'da)
ip route show
# 10.244.2.0/24 via 192.168.1.11 dev eth0  ← CNI tarafından eklendi
```

---

## kube-proxy — Service Trafiği Yönetimi

Service oluşturulduğunda kube-proxy her node'da iptables kuralları yazar:

```
kubectl get svc web-app -n production
# NAME      TYPE        CLUSTER-IP     PORT(S)
# web-app   ClusterIP   10.96.45.100   80/TCP

# Bir pod 10.96.45.100:80'e istek yaptığında:
1. iptables PREROUTING zinciri → KUBE-SERVICES chain
2. Hedef 10.96.45.100:80 → KUBE-SVC-XXXX chain
3. Rastgele pod seç (statistic module ile round-robin)
4. KUBE-SEP-YYYY → DNAT → 10.244.1.5:8080 (gerçek pod IP)
```

```bash
# iptables kurallarını gör (node'da)
iptables -t nat -L KUBE-SERVICES | head -20
iptables -t nat -L KUBE-SVC-XXXXXXXXXXXXXXXX

# Aktif DNAT kuralları
iptables -t nat -L | grep DNAT
```

---

## eBPF Modu (Cilium) — kube-proxy Olmadan

```
iptables yerine kernel'in XDP/TC hook'ları:

Service isteği → eBPF programı kernel'de intercept eder
              → Map'ten pod IP'sini lookup eder
              → DNAT yapar (userspace'e çıkmadan!)
              → Doğrudan pod'a yönlendirir

Avantaj: iptables'tan 3-5x daha hızlı, bağlantı sayısı ölçeklenebilir
```

```bash
# Cilium bağlantı map'lerini gör
cilium map get cilium_lb4_services_v2
cilium map get cilium_lb4_backends_v2

# eBPF programlarını listele
cilium bpf lb list
```

---

## DNS Çözümleme Zinciri

```
Pod içinden: nslookup web-app.production.svc.cluster.local

1. /etc/resolv.conf → nameserver 10.96.0.10 (CoreDNS ClusterIP)
2. Pod → CoreDNS'e UDP/53 sorgusu
3. CoreDNS → Kubernetes API'den Service bilgisini sorgular
4. CoreDNS → A kaydı döner: 10.96.45.100
5. Pod → 10.96.45.100'a bağlanır
6. iptables/eBPF → Gerçek pod IP'sine yönlendirir
```

```bash
# CoreDNS DNS sorgusu izle (tcpdump ile)
kubectl run dns-debug --image=nicolaka/netshoot --rm -it -- bash
tcpdump -i eth0 port 53 -n

# DNS lookup süresi ölç
time nslookup web-app.production.svc.cluster.local
```

---

## Network Namespace İzolasyonu

Her pod kendi Linux network namespace'inde çalışır:

```bash
# Pod'un network namespace'ini bul
POD_ID=$(kubectl get pod <pod> -o jsonpath='{.metadata.uid}')
crictl inspect <container-id> | grep pid

# O process'in network namespace'ini gör (node'da)
nsenter -t <pid> -n -- ip addr
nsenter -t <pid> -n -- ip route
nsenter -t <pid> -n -- ss -tlnp

# Pod'un içindeki bağlantıları gör
nsenter -t <pid> -n -- ss -s
```

---

## Service Türleri ve Trafik Akışı

```
ClusterIP:
  Pod → ClusterIP:Port → iptables DNAT → Pod IP:Port
  Cluster dışından erişilemez

NodePort:
  Dış istemci → NodeIP:NodePort → iptables → Pod IP:Port
  Her node'da aynı port açılır

LoadBalancer:
  İnternet → LB IP → NodePort → Pod IP:Port
  Cloud LB veya MetalLB node'lara trafik dağıtır

ExternalName:
  Pod → DNS → CNAME → external-service.com
  iptables kuralı yok, sadece DNS
```

---

## Trafik Politikası (Traffic Policy)

```yaml
spec:
  type: LoadBalancer
  # internalTrafficPolicy: Cluster (varsayılan) → herhangi pod
  # internalTrafficPolicy: Local → sadece aynı node'daki pod
  externalTrafficPolicy: Local   # Client IP koruma + local pod tercih
  # Dezavantaj: Local pod yoksa istek düşer
```

---

## Network Sorun Giderme Araç Seti

```bash
# Pod içinden debug
kubectl exec -it <pod> -n <ns> -- bash

# Bağlantı testi
curl -v http://web-app.production.svc.cluster.local
curl -v http://10.96.45.100:80   # ClusterIP direkt

# DNS testi
nslookup web-app.production.svc.cluster.local
dig web-app.production.svc.cluster.local

# TCP bağlantısı
nc -zv web-app.production 80

# Paket izleme (netshoot container)
kubectl run netshoot --image=nicolaka/netshoot --rm -it -- bash
tcpdump -i any -n port 8080
mtr web-app.production.svc.cluster.local    # traceroute + ping

# iptables kuralı sayısı (node'da)
iptables -t nat -L | wc -l
# Çok yüksekse (10k+) → eBPF'e geçmeyi düşün
```

---

## Özet: Hangi Katman Neyi Çözer?

| Sorun | Kontrol Yeri |
|:------|:-------------|
| Pod-to-pod bağlantı yok | CNI konfigürasyonu, route tablosu |
| Service IP erişilemiyor | kube-proxy / iptables kuralları |
| DNS çözümlenmiyor | CoreDNS pod durumu, ConfigMap |
| Yavaş bağlantı | iptables kural sayısı, eBPF modu |
| Network Policy engeli | `kubectl describe netpol`, Cilium Hubble |
| LB dış erişim yok | MetalLB, cloud LB, NodePort |
