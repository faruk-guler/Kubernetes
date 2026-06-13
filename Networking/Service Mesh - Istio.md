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

## 6. Istio Ambient Mesh (Sidecar-less Mimarisi)

**Istio Ambient Mesh**, pod'ların içine herhangi bir Envoy proxy (sidecar) enjekte etmeden çalışan yeni nesil bir Service Mesh veri düzlemi (data plane) modudur. Bu mimari, mesh yeteneklerini iki farklı katmana ayırarak kaynak israfını ve operasyonel karmaşıklığı en aza indirir:

1. **L4 Güvenli Taşıma Katmanı (Secure Transport Layer):** Her node üzerinde çalışan **ztunnel** (Zero-Trust Tunnel) adı verilen Rust tabanlı hafif bir daemon ile yönetilir. Servisler arası mTLS şifrelemeyi, kimlik doğrulamayı (authentication) ve L4 yetkilendirme kurallarını üstlenir. Uygulama pod'larında hiçbir değişiklik gerektirmez.
2. **L7 Uygulama İlkesi Katmanı (Application Policy Layer):** Gelişmiş yönlendirme, header manipülasyonu veya rate limiting gibi L7 yetenekleri gerektiğinde, her namespace için isteğe bağlı olarak çalışan bir **Waypoint proxy** (Envoy tabanlı) devreye girer.

```
       [ Uygulama Pod A ]              [ Uygulama Pod B ]
              │                               ▲
              ▼ (L4 Trafiği)                  │ (L4 Trafiği)
       [ Node ztunnel ] ────────mTLS────────► [ Node ztunnel ]
              │                               ▲
              └──────────► [ Waypoint ] ──────┘
                         (İsteğe Bağlı L7)
```

### Ambient Mesh Kurulumu ve Kullanımı

#### 1. Ambient Profili ile Istio Kurulumu

Ambient modu için kurulum profilini belirterek Istio'yu kuruyoruz:

```bash
istioctl install --set profile=ambient -y
```

#### 2. Namespace'i Ambient Moduna Dahil Etme

Otomatik enjeksiyon (sidecar) etiketleri yerine, namespace'i doğrudan Ambient veri düzlemine dahil ediyoruz:

```bash
kubectl label namespace production istio.io/dataplane-mode=ambient
```

Bu etiketleme sonrasında, namespace içindeki pod'ların trafiği otomatik olarak `ztunnel` üzerinden geçmeye başlar ve mTLS ile şifrelenir.

#### 3. L7 Kuralları İçin Waypoint Proxy Tanımlama

Eğer L7 düzeyinde kurallar (örneğin trafik bölme veya HTTP header manipülasyonu) uygulamak istiyorsak, o namespace için bir Waypoint proxy tanımlamalıyız:

```bash
istioctl x waypoint apply --namespace production --name production-waypoint
```

Bu komut arka planda bir Kubernetes Gateway kaynağı oluşturur. Gateway API standartlarına uygun olan bu tanımı deklaratif olarak da uygulayabilirsiniz:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: production-waypoint
  namespace: production
  labels:
    istio.io/waypoint: "true"
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
```

---

## 7. Service Mesh Karşılaştırması (2026)

| Özellik | Istio (Sidecar) | Istio Ambient Mesh | Cilium Service Mesh |
|:---|:---:|:---:|:---:|
| **Sidecar Gereksinimi** | ✅ Evet | ❌ Hayır | ❌ Hayır |
| **Overhead (CPU/RAM)** | Yüksek (~%30) | Düşük (~%5) | Çok Düşük (~%3) |
| **mTLS Desteği** | ✅ Cryptographic (mTLS) | ✅ Cryptographic (mTLS) | ✅ IPsec / WireGuard |
| **L7 Analiz Noktası** | Pod düzeyinde | Namespace düzeyinde (Waypoint) | Node düzeyinde (Envoy) |
| **Kurulum/Yönetim** | Karmaşık | Orta | Basit (Cilium CLI) |

> [!IMPORTANT]
> 2026 yılı itibarıyla Kubernetes ekosisteminde sidecar modellerinden sidecar-less mimarilere (Istio Ambient ve Cilium) geçiş hızlanmıştır. Yeni projelerde kaynak verimliliği ve operasyon kolaylığı nedeniyle öncelikle sidecar-less modelleri tercih edin.

