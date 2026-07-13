# Service Mesh ve Istio Yönetimi

**Service Mesh (Servis Ağı)**, mikroservis mimarilerinde servisler arasındaki ağ trafiğini yöneten, şifreleyen, izleyen ve kontrol eden özel bir altyapı katmanıdır. Kod satırlarında herhangi bir değişiklik yapmadan ağ trafiğine L7 düzeyinde müdahale etme olanağı sunar.

---

## 1. Neden Service Mesh?

Uygulama koduna güvenlik veya izleme kütüphaneleri (SDK) eklemeden şu kurumsal özellikleri kazandırır:

* **Mutual TLS (mTLS):** Servisler arası mTLS şifreleme ve kimlik doğrulama.
* **Trafik Yönetimi:** Canary dağıtımlar, A/B testleri, retry (yeniden deneme) ve Circuit Breaker (devre kesici) mekanizmaları.
* **Gözlemlenebilirlik:** Dağıtık izleme (Distributed Tracing) ve servis bağımlılık grafikleri (Örn: Kiali).

---

## 2. Istio Mimarisi: Sidecar vs Ambient Mesh

Istio iki farklı mimari model sunar:

### A. Sidecar Modeli (Geleneksel)

Her podun içine otomatik olarak bir Envoy proxy konteyneri (Sidecar) enjekte edilir. Podun tüm giriş ve çıkış trafiği bu proxy üzerinden geçer.

* *Sınırlaması:* Her poda eklenen proxy yüksek bellek ve CPU tüketimine yol açar (büyük kümelerde ~%30 kaynak kaybı).

### B. Ambient Mesh Modeli (Sidecar-less)

Konteynerlerin içine proxy enjekte edilmeyen yeni nesil bir mimaridir. Mesh yeteneklerini iki katmana ayırır:

1. **L4 Güvenli Taşıma Katmanı (ztunnel):** Her düğümde çalışan hafif bir daemon (ztunnel - Rust tabanlı) mTLS şifrelemeyi üstlenir.
2. **L7 Uygulama İlkesi Katmanı (Waypoint):** İsteğe bağlı olarak, L7 yönlendirmeler gerektiğinde her namespace için Envoy tabanlı bir Waypoint proxy çalıştırılır.

```
Geleneksel (Sidecar):
  [ Pod A (App + Envoy Proxy) ] ◄─────── mTLS ───────► [ Pod B (App + Envoy Proxy) ]

Modern (Ambient):
  [ Pod A (App) ] ──► [ ztunnel (Node 1) ] ◄── mTLS ──► [ ztunnel (Node 2) ] ──► [ Pod B (App) ]
```

---

## 3. Istio Kurulumu ve Kullanımı

### Istio CLI Kurulumu ve Başlatılması

```bash
# 1. Istio sürümünü indirin (v1.23.0)
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.0 sh -
export PATH=$PWD/istio-1.23.0/bin:$PATH

# 2. Üretim ortamları için minimal profiliyle kurun
istioctl install --set profile=minimal -y

# 3. İlgili isim alanında otomatik sidecar enjeksiyonunu aktifleştirin
kubectl label namespace production istio-injection=enabled
```

### Ambient Modunda Kurulum (Sidecar-less)

Eğer podlara sidecar enjekte etmek istemiyorsanız, Ambient profilini kullanın:

```bash
# 1. Ambient modunda kurulum
istioctl install --set profile=ambient -y

# 2. İsim alanını Ambient moduna dahil edin
kubectl label namespace production istio.io/dataplane-mode=ambient
```

---

## 4. Trafik ve Güvenlik Yapılandırması

Istio üzerinde mTLS güvenliğini ve yönlendirmelerini yönetmek için Custom Resources (CRD) kullanılır:

### A. PeerAuthentication (mTLS Zorunlu Kılma)

Namespace altındaki tüm iletişimde mTLS şifrelemeyi zorunlu kılmak için:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT # STRICT modu şifresiz düz metin (plaintext) bağlantıları reddeder
```

### B. VirtualService (Trafik Yönlendirme)

Gelen HTTP isteklerini path bazlı olarak küme içi servislere dağıtmak için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [service_mesh_istio_manifest_1.yaml](../Manifests/05_networking/service_mesh_istio_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Service Mesh Seçenekleri Karşılaştırma Tablosu

| Kriter | Istio (Sidecar) | Istio Ambient Mesh | Cilium Service Mesh |
| :--- | :--- | :--- | :--- |
| **Sidecar Enjeksiyonu** | ✅ Evet | ❌ Hayır | ❌ Hayır |
| **Ek Kaynak Tüketimi** | Yüksek (~%30 CPU/RAM) | Düşük (~%5) | Çok Düşük (~%3) |
| **mTLS Tipi** | Cryptographic (mTLS) | Cryptographic (mTLS) | WireGuard / IPsec |
| **Yönetim Kolaylığı** | Zor / Karmaşık | Orta | Kolay (Cilium CLI) |
