# Gateway API ile Trafik Yönetimi

2026 yılında Kubernetes'te trafik yönetimi için `Ingress` yerine **Gateway API** standarttır. Gateway API, Ingress'in ek anotasyon gerektiren sınırlı özelliklerini (header manipülasyonu, traffic splitting, TLS) **yerleşik (native)** olarak sunar.

## 1.1 Ingress vs Gateway API

| Özellik | Ingress | Gateway API |
|:---|:---:|:---:|
| Standart | v1 (Stable) | v1 (Stable, 2023+) |
| Role Ayrımı | âŒ | ✅ (Infra/Uygulama/Route) |
| Traffic splitting | Anotasyon | Native |
| Header manipulation | Anotasyon | Native |
| gRPC desteği | Kısıtlı | Native (GRPCRoute) |
| TCP/UDP | âŒ | ✅ |
| Multi-namespace | Kısıtlı | ✅ |

## 1.2 Gateway API CRD Kurulumu

```bash
# Standart kurulum (v1.2.0)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Deneysel kaynaklar için (TCPRoute, GRPCRoute vb.)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/experimental-install.yaml

# Doğrulama
kubectl get crd | grep gateway
```

## 1.3 Temel Kavramlar

Gateway API üç rol üzerine kuruludur:

1. **GatewayClass:** Altyapı ekibi tanımlar — hangi controller kullanılacak (Cilium, Envoy, Istio)
2. **Gateway:** Platform ekibi tanımlar — trafiğin giriş noktası, port, protocol, TLS
3. **HTTPRoute / GRPCRoute:** Uygulama ekibi tanımlar — hangi path'in hangi servise gideceği

## 1.4 İlk Gateway ve HTTPRoute

```yaml
# 1. GatewayClass (Cilium tarafından otomatik oluşturulur)
# kubectl get gatewayclass ile mevcut olanları görebilirsiniz

# 2. Gateway — Dış Trafiğin Giriş Noktası
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: main-tls-secret   # cert-manager tarafından otomatik oluşturulur
    allowedRoutes:
      namespaces:
        from: All
---
# 3. HTTPRoute — Yönlendirme Kuralları
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-app-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
  hostnames:
  - "myapp.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-service
      port: 8080
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-service
      port: 80
```

## 1.5 Traffic Splitting (Canary Deployment)

Gateway API ile trafiği yüzde bazında yeni versiyona yönlendirmek:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary-route
spec:
  parentRefs:
  - name: main-gateway
  rules:
  - backendRefs:
    - name: web-app-v1    # Eski versiyon
      port: 80
      weight: 90          # %90 trafik
    - name: web-app-v2    # Yeni versiyon
      port: 80
      weight: 10          # %10 trafik
```

## 1.6 Header Manipülasyonu

```yaml
rules:
- filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      add:
      - name: X-Custom-Header
        value: "kubernetes-2026"
      remove:
      - "X-Old-Header"
  - type: ResponseHeaderModifier
    responseHeaderModifier:
      add:
      - name: Cache-Control
        value: "max-age=3600"
```

## 1.7 MetalLB — Bare Metal Load Balancer

Bulut sağlayıcı olmayan ortamlarda Gateway'e dış IP atamak için:

```bash
# MetalLB kurulumu (v0.14.8)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Doğrulama
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

**IP Pool ve L2 Advertisement:**

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prod-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.250   # Kendi ağ aralığınıza göre düzenleyin
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - prod-pool
```

> [!TIP]
> BGP modunda MetalLB, gerçek üretim ağlarında çok daha güçlü bir yük dengeleme sağlar. Router'larınız BGP destekliyorsa `BGPAdvertisement` kullanın.

