# Gateway API ile Trafik Yönetimi

Kubernetes'te trafik yönetimi için uzun yıllar boyunca kullanılan klasik `Ingress` yapısı, ek anotasyon gerektiren karmaşık mimarisi ve rol bazlı ayrım sunamaması nedeniyle yerini **Gateway API** standardına bırakmıştır. Gateway API; header manipülasyonu, trafik bölme (canary), TLS sonlandırma gibi işlemleri ek bir anotasyona ihtiyaç duymadan **yerleşik (native)** olarak destekler.

---

## 1. Ingress ve Gateway API Karşılaştırması

| Özellik | Klasik Ingress | Modern Gateway API |
| :--- | :--- | :--- |
| **Standart Seviyesi** | Kısıtlı L7 özellikleri sunar. | L4 (TCP/UDP) ve L7 (HTTP, gRPC) destekler. |
| **Rol Ayrımı (RBAC)** | Tek bir nesne üzerinden yönetilir. | Altyapı, platform ve uygulama ekipleri için ayrılmıştır. |
| **Trafik Bölme (Canary)**| Ek Controller ve anotasyonlar gerektirir.| Doğal olarak (native) ağırlık bazlı yönlendirmeyi destekler. |
| **gRPC Desteği** | Kısıtlıdır. | `GRPCRoute` ile yerleşik destek sunar. |

---

## 2. Gateway API Temel Bileşenleri ve Rol Ayrımı

Gateway API, altyapı yönetimini üç temel kaynağa bölerek ekipler arasındaki yetki karmaşasını çözer:

```
[ Altyapı Sağlayıcı ]  ──► 1. GatewayClass (Hangi controller kullanılacak? Örn: Cilium, Envoy)
       │
[ Platform Ekibi ]     ──► 2. Gateway (Dış dünyaya açık IP, TLS Sertifikası, Port)
       │
[ Uygulama Ekibi ]     ──► 3. HTTPRoute (Yollara göre yönlendirme ve servis eşleme)
```

1. **GatewayClass:** Küme genelinde kullanılacak olan altyapı şablonunu tanımlar. (Örn: Cilium, Envoy, Istio).
2. **Gateway:** Altyapının dış dünya ile buluştuğu noktadır. Giriş IP adresini, dinlenecek portları ve TLS sertifikalarını yönetir.
3. **HTTPRoute / GRPCRoute:** Uygulama geliştiricileri tarafından tanımlanır. Hangi HTTP istek yollarının (path) hangi küme içi servislerine yönlendirileceğini belirtir.

---

## 3. Gateway ve HTTPRoute Yapılandırması

### A. Gateway Tanımı (Platform Ekibi)

Gateway nesnesi, platform ekibi tarafından yönetilir ve altyapının dış dünya ile buluştuğu noktadaki dinleyici portlarını (Port 80/443), giriş IP adresini ve hangi isim alanlarından (namespaces) route kabul edileceğini tanımlar:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-gateway
  namespace: production
spec:
  gatewayClassName: cilium # Altyapı sağlayıcısının GatewayClass ismi (Envoy, Istio vb.)
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: company-wildcard-tls
      allowedRoutes:
        namespaces:
          from: All # Tüm namespace'lerden gelen HTTPRoute isteklerine izin ver
```

### B. HTTPRoute Tanımı (Uygulama Ekibi)

HTTPRoute nesnesi, uygulama geliştiricileri tarafından tanımlanarak gelen HTTP isteklerinin path veya header eşleşmelerine göre küme içi servislere yönlendirilmesini sağlar:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: order-service-route
  namespace: production
spec:
  parentRefs:
    - name: external-gateway # Yukarıdaki Gateway nesnesine bağlanır
  hostnames:
    - "api.company.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v1/orders
      backendRefs:
        - name: order-service
          port: 80
```

---

## 4. Trafik Bölme (Canary Deployment)

Gateway API ile gelen trafiği yüzde bazında iki farklı servise yönlendirmek oldukça basittir. `HTTPRoute` kuralları altında `backendRefs` listesinde yer alan her bir servise `weight` (ağırlık) parametresi atanarak trafik kademeli olarak paylaştırılır:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: order-service-canary-route
  namespace: production
spec:
  parentRefs:
    - name: external-gateway
  hostnames:
    - "api.company.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/v1/orders
      backendRefs:
        - name: order-service-v1
          port: 80
          weight: 80 # Trafiğin %80'i stabil sürüme
        - name: order-service-v2
          port: 80
          weight: 20 # Trafiğin %20'si yeni Canary sürüme
```

---

## 5. GAMMA Spesifikasyonu (Cluster İçi Servis İletişimi)

Gateway API sadece dışarıdan içeriye gelen (North-South) trafiği yönetmekle kalmaz; **GAMMA (Gateway API for Mesh Management and Administration)** spesifikasyonu sayesinde cluster içi (East-West) servislerin kendi aralarındaki iletişimini de yönetebilir.

GAMMA modelinde bir `HTTPRoute` doğrudan bir `Gateway` yerine, bir `Service` nesnesine bağlanır (`parentRef` olarak):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: reviews-mesh-traffic-split
  namespace: default
spec:
  parentRefs:
    - group: ""
      kind: Service
      name: reviews-service # Cluster içi servis hedef alınır
      port: 9080
  rules:
    - backendRefs:
        - name: reviews-v1
          port: 9080
          weight: 90
        - name: reviews-v2
          port: 9080
          weight: 10
```

*Not:* Bu modelde istemci pod `reviews-service` ile konuşmaya devam eder ancak arkadaki Service Mesh (Cilium veya Istio), isteği havada yakalayarak ağırlıklara göre gerçek podlara yönlendirir.

