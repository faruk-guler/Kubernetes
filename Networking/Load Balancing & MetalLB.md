# Load Balancing & MetalLB

Bare-metal Kubernetes cluster'larında `LoadBalancer` tipinde bir Service oluşturduğunuzda `EXTERNAL-IP` alanı sonsuza dek `<pending>` kalır — çünkü bulut sağlayıcısı yoktur. MetalLB bu boşluğu doldurur.

---

## Neden MetalLB?

| Ortam | LoadBalancer Kaynağı |
|:------|:---------------------|
| AWS EKS | AWS ALB/NLB (otomatik) |
| GKE | Google Cloud LB (otomatik) |
| Azure AKS | Azure LB (otomatik) |
| **Bare-metal / On-prem** | **MetalLB** (manuel kurulum) |
| **Kind / k3d / Minikube** | **MetalLB** (lab ortamı) |

---

## MetalLB Çalışma Modları

### Layer 2 Modu (ARP/NDP)
- En basit kurulum
- Bir node, IP için ARP yanıtı verir → tüm trafik o node üzerinden geçer
- Failover: ~10 saniye (ARP yenileme)
- **Gerçek load balancing yok** — tek node bottleneck

### BGP Modu
- Router'larla BGP konuşur
- Gerçek ECMP (Equal-Cost Multi-Path) load balancing
- Her node equal-weight olarak trafiği alır
- Üretim için önerilen mod

---

## Kurulum

```bash
# MetalLB namespace ve CRD'ler
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Pod'ların hazır olmasını bekle
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

---

## Layer 2 Yapılandırması

```yaml
# IP havuzu tanımla
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.10.100-192.168.10.150    # Atanabilir IP aralığı
  - 10.0.0.50/28                      # veya CIDR notasyonu
  autoAssign: true                    # Service'lere otomatik IP ata
---
# Layer2 duyurusunu aktif et
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: production-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - production-pool
  nodeSelectors:                      # Hangi node'lar duyuru yapar
  - matchLabels:
      node-role: worker
```

---

## BGP Yapılandırması

```yaml
# BGP Peer (router) tanımla
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: core-router
  namespace: metallb-system
spec:
  myASN: 64512          # Kubernetes cluster ASN (private range)
  peerASN: 64510        # Router ASN
  peerAddress: 192.168.1.1
  keepaliveTime: 30s
  holdTime: 90s
---
# IP havuzu
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: bgp-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.100.0/24
---
# BGP duyurusu
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - bgp-pool
  communities:
  - 64512:100           # BGP community tag
  localPref: 100
```

---

## Service Kullanımı

```yaml
# Basit LoadBalancer Service
apiVersion: v1
kind: Service
metadata:
  name: web-app
  namespace: production
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
  # MetalLB otomatik IP atar
```

```yaml
# Belirli IP isteği
metadata:
  annotations:
    metallb.universe.tf/address-pool: production-pool
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.10.110    # Belirli IP iste
```

```yaml
# Yalnızca belirli node'lardan duyuru (BGP seçici kullanım)
metadata:
  annotations:
    metallb.universe.tf/node-selectors: '{"kubernetes.io/role": "edge"}'
```

---

## Çoklu IP Havuzu Stratejisi

```yaml
# Production havuzu (kısıtlı erişim)
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: internal-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.0.100-10.0.0.120
  serviceAllocation:
    priority: 50
    namespaces:
    - production
    - staging
---
# Public havuz (DMZ)
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-pool
  namespace: metallb-system
spec:
  addresses:
  - 203.0.113.100-203.0.113.110
  serviceAllocation:
    priority: 100
    namespaces:
    - ingress-nginx    # Sadece ingress controller bu IP'leri alır
```

---

## Sorun Giderme

```bash
# MetalLB pod durumu
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l component=controller
kubectl logs -n metallb-system -l component=speaker

# Service IP atandı mı?
kubectl get svc web-app -n production
# EXTERNAL-IP hâlâ pending → IPAddressPool'da yer var mı?

# IP havuzundaki kullanımı gör
kubectl describe ipaddresspool production-pool -n metallb-system

# Layer2 duyuruları
kubectl get l2advertisements -n metallb-system

# BGP oturumu durumu
kubectl logs -n metallb-system -l component=speaker | grep -i bgp

# ARP tablosunu kontrol et (node'da)
arp -n | grep <external-ip>
```

---

## MetalLB + Ingress Kombinasyonu

```yaml
# En yaygın kullanım: MetalLB → Ingress Controller → Servisler
# Sadece Ingress Controller'ın LoadBalancer IP'si olur

apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer         # MetalLB bu Service'e IP atar
  selector:
    app.kubernetes.io/name: ingress-nginx
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: https
    port: 443
    targetPort: https
```

```
İnternet → MetalLB IP (203.0.113.100)
                │
         Ingress Controller (NGINX)
                │
    ┌───────────┼───────────┐
    ▼           ▼           ▼
 Service A   Service B   Service C
```

> [!TIP]
> k3d ve Kind lab ortamlarında MetalLB kurulumu için IP aralığını Docker bridge network'ünden seçin:
> `docker network inspect kind | grep Subnet` → çıkan subnet'ten bir aralık alın.
