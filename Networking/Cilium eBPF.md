# Cilium & eBPF

Cilium, Linux çekirdeğindeki eBPF teknolojisini kullanarak Kubernetes ağını yöneten CNCF Graduated bir CNI projesidir. 2026 itibarıyla `kube-proxy + iptables` kombinasyonunun yerini almıştır.

---

## Neden Cilium?

```
Eski yol (kube-proxy + iptables):
  Pod → iptables kuralları (~10.000 kural büyük clusterlarda) → hedef
  Sorun: Her kural = linear arama, gecikme büyür

Cilium (eBPF):
  Pod → eBPF haritası (hash table, O(1) arama) → hedef
  Artı: Daha hızlı, L7 görünürlük, mTLS, network policy
```

**eBPF nedir?**
Kernel kaynak kodunu değiştirmeden kernel space'de güvenli program çalıştırma teknolojisi. Cilium bunu network, güvenlik ve observability için kullanır.

---

## Kurulum

```bash
# Helm ile Cilium kurulumu (kube-proxy yerine)
helm repo add cilium https://helm.cilium.io/

# kubeadm cluster'da — kube-proxy olmadan
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<CONTROL_PLANE_IP> \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true

# Kurulum doğrulama
cilium status
cilium connectivity test
```

```bash
# Mevcut cluster'da kube-proxy'yi devre dışı bırak
kubectl -n kube-system delete ds kube-proxy
kubectl -n kube-system delete cm kube-proxy
iptables-save | grep -v KUBE | iptables-restore
```

---

## eBPF Temel Kavramlar

```
BPF Map     → Kernel ve userspace arasında paylaşılan veri yapısı
BPF Program → Kernel olaylarına bağlı (packet in/out, syscall) güvenli kod
BPF Hook    → tc (traffic control), XDP, kprobe, tracepoint noktaları

Cilium bileşenleri:
  cilium-agent  → Her node'da çalışır, eBPF programlarını yükler
  cilium-operator → Cluster-wide kaynakları (IPAM, CiliumNode) yönetir
  Hubble        → eBPF tabanlı network observability
```

---

## CiliumNetworkPolicy

Kubernetes `NetworkPolicy`'den daha güçlü L3/L4/L7 politikalar:

```yaml
# L3/L4 — Kaynak IP + Port kontrolü
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
```

```yaml
# L7 — HTTP path/method kontrolü (Cilium'a özgü!)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-http-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: GET
          path: "/api/v1/.*"
        - method: POST
          path: "/api/v1/orders"
```

```yaml
# DNS tabanlı egress kısıtı (cluster dışına)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-external-api
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: payment-service
  egress:
  - toFQDNs:
    - matchName: "api.stripe.com"
    - matchName: "api.paypal.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
```

---

## kube-proxy Yerine Cilium (Karşılaştırma)

```yaml
# Cilium kurulumda kube-proxy tamamen atlatılır
helm install cilium cilium/cilium \
  --set kubeProxyReplacement=true
# Bu modda:
# ✅ ClusterIP Service → eBPF ile
# ✅ NodePort Service  → eBPF ile
# ✅ LoadBalancer      → eBPF ile
# ✅ ExternalIPs       → eBPF ile
# ❌ kube-proxy        → çalışmıyor, gerek yok
```

---

## Hubble — Network Observability

```bash
# Hubble CLI kurulumu
export HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all \
  "https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz"
tar xzvf hubble-linux-amd64.tar.gz
sudo mv hubble /usr/local/bin/

# Hubble relay'e bağlan
cilium hubble port-forward &

# Canlı trafik izleme
hubble observe --follow
hubble observe --namespace production --follow
hubble observe --pod frontend-xxx --protocol tcp --port 8080

# Flow durumunu görüntüle
hubble observe --verdict DROPPED    # Engellenen paketler
hubble observe --verdict FORWARDED  # İletilen paketler

# Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# http://localhost:12000
```

---

## Cilium Service Mesh (Istio Alternatifi)

```bash
# mTLS + L7 policy için Istio gerekmez
helm upgrade cilium cilium/cilium \
  --set kubeProxyReplacement=true \
  --set socketLB.enabled=true \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true \
  --set hostPort.enabled=true \
  --set bpf.masquerade=true \
  --set encryption.enabled=true \
  --set encryption.type=wireguard   # Node arası WireGuard şifreleme
```

---

## Prometheus Metrikleri

```promql
# Dropped network paketleri
sum(rate(cilium_drop_count_total[5m])) by (reason, namespace)

# Policy enforce ihlalleri
sum(rate(cilium_policy_l7_denied_total[5m])) by (namespace)

# Endpoint health
cilium_endpoint_state{state="ready"} / cilium_endpoint_state

# eBPF map doluluk oranı
cilium_bpf_map_pressure > 0.8   # %80 üstü uyarı
```

---

## Sorun Giderme

```bash
# Cilium agent durumu
kubectl -n kube-system exec -it ds/cilium -- cilium status --verbose

# Endpoint listesi
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list

# Belirli pod'un politikalarını görüntüle
kubectl -n kube-system exec -it ds/cilium -- \
  cilium endpoint get <endpoint-id>

# eBPF politika durumu
kubectl -n kube-system exec -it ds/cilium -- \
  cilium policy get

# Connectivity test (kapsamlı)
cilium connectivity test --test-namespace cilium-test

# Log analizi
kubectl -n kube-system logs -l k8s-app=cilium --tail=100

# iptables kurallarının temizlendiğini doğrula
iptables -L -n | grep -i kube | wc -l  # 0 olmalı
```

> [!TIP]
> `cilium status` çıktısında `KubeProxyReplacement: True` görüyorsanız Cilium tam eBPF modunda çalışıyor demektir. Her ortamda bunu doğrulayın.

> [!WARNING]
> Cilium'u mevcut cluster'a ekliyorsanız, `kube-proxy` DaemonSet'ini silmeden önce `cilium connectivity test` geçtiğinden emin olun. Sıra önemli.
