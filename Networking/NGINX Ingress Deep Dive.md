# NGINX Ingress Deep Dive

NGINX Ingress Controller, Kubernetes'in en yaygın HTTP yük dengeleyicisidir. Basit bir reverse proxy'nin çok ötesinde: rate limiting, authentication, canary, custom headers ve WAF özelliklerini annotations ile sağlar.

---

## Kurulum

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.service.type=LoadBalancer \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.podAntiAffinity.enabled=true \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.limits.cpu=2 \
  --set controller.resources.limits.memory=1Gi
```

---

## Temel Ingress Yapılandırması

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - api.company.com
    secretName: api-tls-secret

  rules:
  - host: api.company.com
    http:
      paths:
      - path: /api/v1
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /static
        pathType: Prefix
        backend:
          service:
            name: static-service
            port:
              number: 80
```

---

## Kritik Annotations

### Timeout & Buffer

```yaml
metadata:
  annotations:
    # Backend'den yanıt bekleme süresi (saniye)
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"

    # Büyük dosya yükleme için
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
```

### Rate Limiting

```yaml
metadata:
  annotations:
    # IP başına saniyede 10 istek
    nginx.ingress.kubernetes.io/limit-rps: "10"

    # IP başına dakikada 100 istek
    nginx.ingress.kubernetes.io/limit-rpm: "100"

    # IP başına eş zamanlı bağlantı
    nginx.ingress.kubernetes.io/limit-connections: "20"

    # Rate limit bypass (güvenilir IP'ler)
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8,172.16.0.0/12"
```

### CORS

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://app.company.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "Authorization, Content-Type"
    nginx.ingress.kubernetes.io/cors-max-age: "3600"
```

### Authentication (Basic Auth)

```bash
# htpasswd ile kullanıcı oluştur
htpasswd -c auth admin
kubectl create secret generic basic-auth \
  --from-file=auth \
  -n production
```

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Protected Area"
```

### OAuth2 / SSO (oauth2-proxy ile)

```yaml
metadata:
  annotations:
    # Tüm istekleri oauth2-proxy üzerinden geçir
    nginx.ingress.kubernetes.io/auth-url: "https://oauth.company.com/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://oauth.company.com/oauth2/start?rd=$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email"
```

### Canary Deployment

```yaml
# Stabil sürüm
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-stable
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: api.company.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: api-v1
            port: {number: 8080}
---
# Canary sürüm — %10 trafik
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-canary
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"     # %10 trafik
    # veya header bazlı:
    # nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"
    # nginx.ingress.kubernetes.io/canary-by-header-value: "true"
spec:
  rules:
  - host: api.company.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: api-v2
            port: {number: 8080}
```

---

## Custom Headers & Rewrites

```yaml
metadata:
  annotations:
    # Header ekle/değiştir
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-Frame-Options: SAMEORIGIN";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Strict-Transport-Security: max-age=31536000";

    # URL rewrite
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    # /api/v1/users → /users
    # path: /api/v1(/|$)(.*)

    # Redirect
    nginx.ingress.kubernetes.io/permanent-redirect: "https://new.company.com"
    nginx.ingress.kubernetes.io/permanent-redirect-code: "301"
```

---

## SSL/TLS & Cert-Manager Entegrasyonu

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256"
spec:
  tls:
  - hosts:
    - api.company.com
    secretName: api-tls   # cert-manager otomatik doldurur
  rules:
  - host: api.company.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port: {number: 8080}
```

---

## Global Yapılandırma (ConfigMap)

```yaml
# ingress-nginx namespace'indeki ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Gerçek client IP'yi logla (LB arkasında)
  use-forwarded-headers: "true"
  compute-full-forwarded-for: "true"
  use-proxy-protocol: "false"

  # Keep-alive
  keep-alive: "75"
  keep-alive-requests: "1000"

  # Log formatı (JSON)
  log-format-upstream: '{"time":"$time_iso8601","remote_addr":"$remote_addr","x_forwarded_for":"$http_x_forwarded_for","request_id":"$req_id","status":$status,"request_time":$request_time,"upstream_response_time":"$upstream_response_time","request":"$request","http_user_agent":"$http_user_agent"}'

  # Worker sayısı
  worker-processes: "auto"

  # Body size limiti (global)
  proxy-body-size: "50m"

  # Gzip
  use-gzip: "true"
  gzip-types: "application/json text/plain application/xml"
```

---

## Prometheus Metrikleri

```promql
# Ingress başarı oranı
sum(rate(nginx_ingress_controller_requests{status!~"5.."}[5m])) by (ingress) /
sum(rate(nginx_ingress_controller_requests[5m])) by (ingress)

# Backend yanıt süresi (P99)
histogram_quantile(0.99,
  sum(rate(nginx_ingress_controller_response_duration_seconds_bucket[5m])) by (le, ingress)
)

# Aktif bağlantı sayısı
nginx_ingress_controller_nginx_process_connections{state="active"}
```

---

## Sorun Giderme

```bash
# Ingress controller logları
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# NGINX yapılandırmasını kontrol et
kubectl exec -n ingress-nginx \
  $(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o name | head -1) \
  -- nginx -t

# Reload sayısı (sık reload → performans sorunu)
kubectl exec -n ingress-nginx ... -- curl localhost:10246/metrics | grep reload

# Ingress objesinin backend'i çözmüş mü?
kubectl describe ingress api-ingress -n production
# "Backends" satırını kontrol et — IP görünüyor mu?
```
