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

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gateway_api_manifest_1.yaml](../Manifests/05_networking/gateway_api_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. HTTPRoute Tanımı (Uygulama Ekibi)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gateway_api_manifest_2.yaml](../Manifests/05_networking/gateway_api_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Trafik Bölme (Canary Deployment)

Gateway API ile gelen trafiği yüzde bazında iki farklı servise yönlendirmek oldukça basittir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gateway_api_manifest_3.yaml](../Manifests/05_networking/gateway_api_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. GAMMA Spesifikasyonu (Cluster İçi Servis İletişimi)

Gateway API sadece dışarıdan içeriye gelen (North-South) trafiği yönetmekle kalmaz; **GAMMA (Gateway API for Mesh Management and Administration)** spesifikasyonu sayesinde cluster içi (East-West) servislerin kendi aralarındaki iletişimini de yönetebilir.

GAMMA modelinde bir `HTTPRoute` doğrudan bir `Gateway` yerine, bir `Service` nesnesine bağlanır (parentRef olarak).

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gateway_api_manifest_4.yaml](../Manifests/05_networking/gateway_api_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

*Not:* Bu modelde istemci pod reviews-service ile konuşmaya devam eder ancak arkadaki Service Mesh (Cilium veya Istio), isteği havada yakalayarak ağırlıklara göre gerçek podlara yönlendirir.
