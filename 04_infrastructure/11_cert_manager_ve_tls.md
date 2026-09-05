# Otomatik TLS ve Sertifika Yönetimi: Cert-Manager

Üretim (production) ortamlarında çalışan tüm web uygulamalarının ve API servislerinin TLS (SSL) sertifikaları ile şifrelenmesi zorunludur. Ancak onlarca veya yüzlerce mikroservisin sertifikalarını elle üretmek, süresi dolduğunda (genellikle 90 günde bir) yenilemeyi unutmak ve panik anında kesintilerle karşılaşmak operasyonel bir kabustur.

**Cert-Manager**, Kubernetes kümelerinde X.509 dijital sertifikalarının temin edilmesini, doğrulanmasını ve süreleri dolmadan otomatik yenilenmesini sağlayan CNCF onaylı endüstri standardı sertifika denetleyicisidir. Let's Encrypt, HashiCorp Vault, Venafi veya kurum içi Özel Sertifika Otoriteleri (Private CA) ile doğrudan konuşur.

---

## 1. Cert-Manager Mimarisi ve Bileşenleri

Cert-Manager kümede bağımsız podlar halinde çalışır ve Kubernetes API'sini genişleten Özel Kaynak Tanımları (CRD) sunar:

```text
┌────────────────────────────────────────────────────────┐
│                   Kubernetes Ingress                   │
│         (cert-manager.io/cluster-issuer: letsencrypt)  │
└───────────────────────────┬────────────────────────────┘
                            │ (Tetikler)
                            ▼
┌────────────────────────────────────────────────────────┐
│               Cert-Manager Controller                  │
│  - Certificate ──► CertificateRequest ──► Order        │
└───────────────────────────┬────────────────────────────┘
                            │
               ┌────────────┴────────────┐
               ▼                         ▼
      ┌─────────────────┐       ┌─────────────────┐
      │ HTTP-01 Solver  │       │ DNS-01 Provider │
      │ (Geçici Pod/Ing)│       │ (Route53/CF/API)│
      └────────┬────────┘       └────────┬────────┘
               │                         │
               └────────────┬────────────┘
                            ▼
┌────────────────────────────────────────────────────────┐
│            Let's Encrypt / CA Otoritesi                │
│       (Doğrulama Sonrası İmzalı Sertifika)            │
└───────────────────────────┬────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────┐
│               Kubernetes Secret: TLS                   │
│           (tls.crt + tls.key montajı)                  │
└────────────────────────────────────────────────────────┘
```

* **`cert-manager-controller`:** Sertifikaların yaşam döngüsünü, geçerlilik sürelerini ve yenileme zamanlarını takip eder.
* **`cert-manager-webhook`:** CRD'lerin doğruluğunu (validation ve mutation) denetler.
* **`cert-manager-cainjector`:** Webhook ve API bileşenlerinin iç iletişimde ihtiyaç duyduğu sertifikaları ilgili nesnelere enjekte eder.

---

## 2. Temel Kavramlar: Issuer vs. ClusterIssuer

Sertifika otoriteleriyle konuşabilmek için öncelikle bir yetki sağlayıcı tanımlanır:

* **`Issuer`:** Yalnızca tanımlandığı tek bir namespace (ad alanı) içindeki sertifika taleplerini karşılar.
* **`ClusterIssuer`:** Küme genelinde geçerlidir. Tüm namespace'lerdeki Ingress ve Certificate kaynakları bu sağlayıcıyı ortak kullanabilir.

---

## 3. Let's Encrypt ile ClusterIssuer Yapılandırması

Let's Encrypt iki temel doğrulama yöntemi (challenge) sunar:

### A. HTTP-01 Challenge (Web Sunucusu Doğrulaması)

Alan adının (`api.company.com`) ilgili Kubernetes kümesine yönlendirildiğini kanıtlamak için Cert-Manager geçici bir HTTP podu ve yönlendirme kuralı açar:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: devops@company.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
```

### B. DNS-01 Challenge (Wildcard ve İç Ağ Sertifikaları)

Dış dünyadan erişilemeyen iç ağ servisleri veya joker (`*.company.com`) sertifikalar için DNS sağlayıcı API'si (Cloudflare, AWS Route53 vb.) üzerinden `_acme-challenge` TXT kaydı açılarak doğrulama yapılır.

---

## 4. Ingress ile Otomatik Sertifika Temini

Bir mikroservisi dışa açarken Ingress manifestosuna yalnızca tek bir açıklama (annotation) eklemeniz yeterlidir:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: payment-api-ingress
  namespace: production
  annotations:
    # Cert-manager'a hangi ClusterIssuer'ı kullanacağını belirtin:
    cert-manager.io/cluster-issuer: "letsencrypt-production"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - payment.company.com
      secretName: payment-api-tls # Cert-Manager sertifikayı buraya kaydeder
  rules:
    - host: payment.company.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 8080
```

* Ingress uygulandığı anda Cert-Manager otomatik olarak bir `Certificate` nesnesi oluşturur, HTTP-01 doğrulamasını tamamlar ve imzalı sertifikayı `payment-api-tls` isimli Kubernetes Secret'ına yazar.

---

## 5. Müstakil `Certificate` Tanımı (gRPC / Dahili mTLS)

Ingress haricinde, servisler arası mTLS veya dahili TCP bağlantıları için doğrudan bir `Certificate` kaynağı da oluşturabilirsiniz:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-grpc-cert
  namespace: production
spec:
  secretName: internal-grpc-tls
  duration: 2160h # 90 gün
  renewBefore: 360h # Süre bitimine 15 gün kala otomatik yenile
  commonName: internal-grpc.production.svc.cluster.local
  dnsNames:
    - internal-grpc.production.svc.cluster.local
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
```

---

## 6. Sertifika Sorunlarını Giderme (Troubleshooting)

Sertifika `Ready: False` durumunda kalırsa Cert-Manager'ın alt katman nesneleri şu sırayla incelenir:

```bash
# 1. Genel sertifika durumunu denetleyin
kubectl get certificate -n production

# 2. Sertifika sipariş durumunu (Order) inceleyin
kubectl get orders -n production
kubectl describe order <order-adi> -n production

# 3. Doğrulama sınavını (Challenge) denetleyin
kubectl get challenges -n production
kubectl describe challenge <challenge-adi> -n production
```

* **En Sık Karşılaşılan Hata:** DNS A kaydının küme Ingress IP'sine henüz yönlenmemiş olması veya firewall'un 80 portunu Let's Encrypt sunucularına kapatmış olmasıdır.

---

## Özet

Cert-Manager, modern altyapılarda manuel sertifika yenileme dönemini tamamen kapatmıştır. Küme genelinde tanımlanan tek bir `ClusterIssuer` ile geliştiriciler, Ingress tanımlarına sadece tek bir satır ekleyerek uçtan uca güvenli HTTPS erişimi sağlayabilir.
