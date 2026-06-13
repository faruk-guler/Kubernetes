# Cert-manager ve TLS Otomasyonu

## Cert-manager Nedir?

Güvenli web trafiği için TLS sertifikalarına ihtiyacımız var. 2026'da sertifikaları manuel olarak yenilemek kabul edilemez bir hatadır. **Cert-manager**, sertifika otoritesinden (Let's Encrypt, Vault, kendi CA) sertifika alıp süresi dolmadan **otomatik yenilenmesini** sağlar.

## Kurulum

```bash
# OCI Registry üzerinden (2026 standardı)
helm install cert-manager \
  oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true     # 2026 güncel parametre (installCRDs deprecated)
```

## ClusterIssuer — Let's Encrypt

```yaml
# Staging (test için — gerçek sertifika değil, rate limit yok)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: main-gateway
            namespace: default
            kind: Gateway
---
# Production (gerçek sertifika)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - dns01:              # DNS challenge (wildcard sertifika için gerekli)
        route53:
          region: eu-west-1
          hostedZoneID: Z1234567890
```

## Gateway API ile HTTPS

Aşağıdaki örnekte bir Gateway nesnesine cert-manager anotasyonu eklenerek otomatik TLS sağlanır:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    protocol: HTTP
    port: 80
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: main-tls          # Cert-manager bu secret'ı otomatik oluşturur
        kind: Secret
        namespace: default
    allowedRoutes:
      namespaces:
        from: All
```

## Certificate Nesnesi

```yaml
# Wildcard sertifika örneği
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com
  namespace: production
spec:
  secretName: wildcard-example-com-tls
  duration: 2160h      # 90 gün
  renewBefore: 360h    # Süresi dolmadan 15 gün önce yenile
  dnsNames:
  - "example.com"
  - "*.example.com"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

## Sertifika Durumu Kontrolü

```bash
# Sertifika durumu
kubectl get certificate -A
kubectl describe certificate wildcard-example-com -n production

# cert-manager logları
kubectl logs -n cert-manager deployment/cert-manager | tail -50

# Sertifikanın ne zaman dolacağını gör
kubectl get secret wildcard-example-com-tls -n production \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

> [!CAUTION]
> Neden manuel sertifika kullanmamalısınız?
> - **İnsan hatası:** Yenilemeyi unutmak sitenizin 3:00'da çökmesine neden olur
> - **Güvenlik:** 90 günlük kısa süreli sertifikalar daha güvenlidir
> - **Ölçek:** 1000 mikroservisiniz olduğunda manuel yönetim imkansızdır

---
