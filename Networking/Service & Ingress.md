# Service & Ingress

Kubernetes'te pod'lara sabit bir ağ adresi ve dış erişim sağlamak Service ve Ingress/Gateway API nesneleri ile yapılır.

---

## Service Türleri

### ClusterIP (Varsayılan)

Sadece cluster içinden erişilebilir. Servis keşfi (service discovery) için temel yapı taşı.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: production
spec:
  type: ClusterIP
  selector:
    app: api            # Bu label'a sahip pod'lara yönlendir
  ports:
  - name: http
    port: 80            # Service portu
    targetPort: 8080    # Pod portu
  - name: grpc
    port: 9090
    targetPort: 9090
```

```bash
# Cluster içinden erişim
curl http://api-service.production.svc.cluster.local:80
curl http://api-service:80    # Aynı namespace'deyse kısa isim yeter
```

### NodePort

Her node'un IP'sinden belirli bir port üzerinden erişim (30000-32767):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 31000     # Belirtilmezse otomatik atanır
```

> [!NOTE]
> NodePort production için önerilmez. LoadBalancer veya Gateway API kullanın.

### LoadBalancer

Cloud sağlayıcıdan external IP alır. Bare-metal'de MetalLB ile kullanılır:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-lb
  namespace: production
  annotations:
    # AWS NLB (Network Load Balancer)
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    # GCP
    # cloud.google.com/load-balancer-type: "External"
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 443
    targetPort: 8443
  loadBalancerSourceRanges:    # IP whitelist
  - 10.0.0.0/8
  - 203.0.113.0/24
```

### ExternalName

Cluster içinden dış servislere DNS alias:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
  namespace: production
spec:
  type: ExternalName
  externalName: prod-db.company.com    # DNS'e yönlendir
```

### Headless Service (StatefulSet için)

ClusterIP yok — DNS her pod'u ayrı döndürür:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None    # Headless
  selector:
    app: postgres
  ports:
  - port: 5432
```

```bash
# Headless service DNS — her pod ayrı kayıt
# postgres-0.postgres-headless.production.svc.cluster.local
# postgres-1.postgres-headless.production.svc.cluster.local
```

---

## Endpoint & EndpointSlice

```bash
# Service'e bağlı pod IP'lerini gör
kubectl get endpoints api-service -n production
kubectl get endpointslices -n production -l kubernetes.io/service-name=api-service

# Pod bağlantısı yoksa (Endpoints boş):
kubectl describe svc api-service -n production  # selector kontrol
kubectl get pods -n production -l app=api       # label eşleşiyor mu?
```

---

## Ingress (Klasik — Gateway API'ye Geçiş Sürecinde)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.company.com
    secretName: app-tls-cert
  rules:
  - host: app.company.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

---

## Gateway API (2026 Standardı)

Ingress'in sınırlamalarını aşan, daha güçlü ve rol bazlı ağ yönetimi:

```yaml
# GatewayClass — hangi controller kullanılacak
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller

---
# Gateway — giriş noktası (platform ekibi yönetir)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: production-gateway
  namespace: infra
spec:
  gatewayClassName: cilium
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: wildcard-tls-cert
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            gateway: allowed

---
# HTTPRoute — uygulama ekibi yönetir
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: production
spec:
  parentRefs:
  - name: production-gateway
    namespace: infra
  hostnames:
  - "api.company.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v2
    backendRefs:
    - name: api-v2-service
      port: 80
      weight: 90
    - name: api-v3-service
      port: 80
      weight: 10    # Canary — %10 v3'e gönder
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: api-v2-service
      port: 80
```

---

## Session Affinity (Yapışkan Session)

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600    # 1 saat
```

---

## Servis Keşfi (Service Discovery)

```bash
# Kubernetes DNS otomatik kayıt oluşturur
# Format: <service>.<namespace>.svc.cluster.local

# Aynı namespace'deki servis
curl http://api-service

# Farklı namespace
curl http://api-service.production.svc.cluster.local

# DNS'i test et
kubectl run tmp --image=busybox --rm -it -- \
  nslookup api-service.production.svc.cluster.local
```

---

## Sorun Giderme

```bash
# Service endpoint'leri var mı?
kubectl get ep api-service -n production
# Endpoints: <none> → selector eşleşmiyor!

# Pod hazır mı?
kubectl get pods -n production -l app=api
# READY 0/1 → readinessProbe geçmiyor

# Service'ten pod'a bağlantı testi
kubectl run debug --image=nicolaka/netshoot --rm -it -- \
  curl -v http://api-service.production.svc.cluster.local

# kube-proxy (veya Cilium) kuralları
kubectl -n kube-system exec -it ds/cilium -- \
  cilium service list | grep api-service

# Port forward ile direkt test
kubectl port-forward svc/api-service 8080:80 -n production
curl http://localhost:8080/healthz
```

> [!TIP]
> 2026'da yeni projeler için **Gateway API** kullanın. Ingress hâlâ çalışıyor ama aktif geliştirme Gateway API üzerinden ilerliyor. `nginx.ingress.kubernetes.io` annotation'larının Gateway API karşılıklarını öğrenin.
