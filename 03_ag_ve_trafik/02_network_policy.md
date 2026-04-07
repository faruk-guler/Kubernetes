# NetworkPolicy ve Cilium L7 Güvenlik

## 2.1 NetworkPolicy Nedir?

NetworkPolicy, pod'lar arasındaki ağ trafiğini kontrol eden güvenlik kurallarıdır. **Varsayılan olarak Kubernetes'te her pod her pod'a ulaşabilir** — bu üretim için kabul edilemez.

### Varsayılan Deny-All (Önerilen Başlangıç)

```yaml
# Namespace'deki tüm ingress trafiğini engelle
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}      # Namespace'deki tüm pod'lar
  policyTypes:
  - Ingress
---
# Namespace'deki tüm egress trafiğini engelle
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
```

## 2.2 Temel NetworkPolicy Örnekleri

### Belirli Pod'lara İzin Ver

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend    # Bu policy backend pod'larına uygulanır
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend   # Sadece frontend'den gelen trafiğe izin ver
    ports:
    - protocol: TCP
      port: 8080
```

### DNS Erişimine İzin Ver (Egress)

```yaml
# DNS her zaman açık olmalı, aksi hÃ¢lde servis keşfi çalışmaz
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

### Farklı Namespace'ten Erişim

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: my-app
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring   # monitoring namespace'inden
      podSelector:
        matchLabels:
          app: prometheus                            # sadece prometheus'tan
```

## 2.3 Cilium Network Policy (L7)

Standart Kubernetes NetworkPolicy yalnızca L3/L4 (IP, Port) seviyesinde çalışır. Cilium ile **L7 (HTTP path, gRPC method)** seviyesinde kural yazabilirsiniz:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-http-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: backend-api
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
          path: "/api/v1/.*"      # Sadece GET /api/v1/* izinli
        - method: POST
          path: "/api/v1/users"   # POST sadece bu endpoint'e
```

### DNS tabanlı Egress Politikası

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-external-dns
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  egress:
  - toFQDNs:
    - matchName: "api.github.com"
    - matchPattern: "*.stripe.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
```

> [!TIP]
> Cilium'un DNS-aware egress politikaları, dışarıya açılması gereken servisleri IP yerine domain adıyla kısıtlamanızı sağlar. Bu, dinamik IP değişimlerinde politikayı güncelleme ihtiyacını ortadan kaldırır.

