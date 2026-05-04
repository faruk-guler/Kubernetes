# Istio ve Service Mesh

> [!NOTE]
> **2026 Notu:** Cilium 1.15+ ile gelen **Ambient Mesh** modu, Istio'nun sidecar modelini bypass ederek çok daha düşük overhead ile service mesh yetenekleri sunmaktadır. Yeni projeler için önce Cilium Mutual Auth ve L7 policy özelliklerini değerlendirin; sidecar tabanlı Istio'yu yalnızca çok karmaşık trafik yönetimi gerektiğinde kullanın.

---

## 1. Service Mesh Nedir?

**Service Mesh**, mikroservisler arasındaki tüm iletişimi yöneten bir altyapı katmanıdır. Uygulamaya kod eklemeden şunları sağlar:

- Servisler arası **mTLS** (Mutual TLS) şifreleme
- **Traffic splitting** (Canary, A/B testleri)
- **Retry, timeout, circuit breaker**
- **Gözlemlenebilirlik** (her servis çağrısı izlenir)

---

## 2. Mimari: Data Plane ve Control Plane

```
┌─────────────────────────────────────────┐
│         CONTROL PLANE (istiod)          │
│  • Sertifika dağıtımı                   │
│  • Yönlendirme kurallarını Envoy'a ilet │
└──────────────────┬──────────────────────┘
                   │ xDS API
       ┌───────────┼───────────┐
       ▼           ▼           ▼
   [Envoy]     [Envoy]     [Envoy]
   ↕ App A     ↕ App B     ↕ App C
```

**Sidecar (Envoy Proxy):** Her pod'a otomatik eklenen ve tüm trafiği intercept eden C++ proxy.

---

## 3. Istio Kurulumu

```bash
# Istio CLI indir
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.0 sh -
export PATH=$PWD/istio-1.23.0/bin:$PATH
istioctl --version

# Minimal profili ile kurulum (production için)
istioctl install --set profile=minimal -y

# Kurulum doğrulama
istioctl verify-install
kubectl get pods -n istio-system
```

### Sidecar Injection

Namespace'e label ekleyerek otomatik sidecar injection:

```bash
kubectl label namespace production istio-injection=enabled

# Kontrol
kubectl get namespace production --show-labels
```

---

## 4. Temel Kaynaklar

### VirtualService — Trafik Yönlendirme

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: reviews
  namespace: production
spec:
  hosts:
  - reviews
  http:
  - match:
    - headers:
        end-user:
          exact: test-user
    route:
    - destination:
        host: reviews
        subset: v2         # Test kullanıcıları v2'ye
  - route:
    - destination:
        host: reviews
        subset: v1
        weight: 90
    - destination:
        host: reviews
        subset: v2
        weight: 10         # %10 canary
```

### DestinationRule — Pod Seçimi

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: reviews
  namespace: production
spec:
  host: reviews
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL   # mTLS aktif
    connectionPool:
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

### PeerAuthentication — mTLS Zorunlu Kıl

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT     # Tüm servisler arası trafik mTLS ile şifrelensin
```

---

## 5. Gözlemlenebilirlik

```bash
# Kiali dashboard (Istio'nun görsel UI'ı)
kubectl port-forward svc/kiali -n istio-system 20001:20001
# http://localhost:20001

# Jaeger (distributed tracing)
kubectl port-forward svc/jaeger-query -n istio-system 16686:16686
# http://localhost:16686
```

---

## 6. Cilium vs Istio (2026 Değerlendirmesi)

| Özellik | Istio (Sidecar) | Cilium Ambient Mesh |
|:--------|:---------------:|:-------------------:|
| Overhead (CPU/RAM) | Yüksek (~%30) | Çok Düşük (~%5) |
| mTLS | ✅ | ✅ |
| L7 Policy | ✅ | ✅ |
| Kurulum karmaşıklığı | Yüksek | Düşük |
| Sidecar gereksinimi | ✅ Zorunlu | ❌ |
| Olgunluk | Yüksek | Orta (gelişiyor) |

> [!IMPORTANT]
> Istio, gerçek dünyada hâlâ yaygın kullanımdadır. Ancak Cilium Ambient Mesh'in olgunlaşmasıyla birlikte 2027-2028'de standart değişecektir. Yeni greenfield projeler için Ambient Mesh'i değerlendirin.
