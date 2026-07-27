# Aşamalı Teslimat ve A/B Test (Progressive Delivery Guide)

**Aşamalı Teslimat (Progressive Delivery)**, yeni yazılım sürümlerini (updates) tüm kullanıcılara aynı anda açmak yerine, kademeli ve kontrollü bir biçimde yayarak üretim (production) kesintisi riskini en aza indiren modern bir yayınlama metodolojisidir. Bu yöntem; Canary, Blue/Green ve A/B Testing tekniklerini otomatik metrik analizleri ve kendi kendine geri alma (self-healing/auto-rollback) mekanizmalarıyla birleştirir.

---

## 1. Mimarisi ve Temel Kavramlar

```
Geleneksel Dağıtım (Riskli):
  [ Sürüm 1 (Trafik %100) ] ──► (Tek Seferde Değişim) ──► [ Sürüm 2 (Trafik %100) ]

Aşamalı Teslimat (Güvenli):
  [ Sürüm 1 ] ──► [ Kademeli Canary (%5 ──► %20 ──► %50) ] ──► [ Sürüm 2 ]
                        │
                        ▼ (Metrik Denetimi - Prometheus)
                     Hata Var mı? ──► Evetse ──► Otomatik Rollback!
```

Sistemde kullanılan popüler araçlar:

* **Argo Rollouts:** Argo projesinin Kubernetes-native progresif dağıtım aracı.
* **Flagger:** FluxCD ile uyumlu çalışan, NGINX Ingress ve modern **Gateway API** destekli alternatif progresif dağıtım aracı.
* **Flagsmith / LaunchDarkly:** Kod düzeyinde özellik açma/kapatmayı (Feature Flags) sağlayan SaaS araçları.

---

## 2. Argo Rollouts: Canary ve Analiz Yapılandırması

Canary stratejisinde, yeni sürümün çalışması arka planda sürekli denetlenir.

### A. Canary Adımları ve Analiz Entegrasyonu

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_1.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. `AnalysisTemplate` (Başarı Oranı ve Gecikme Denetimi)

Yukarıdaki Rollout'un her adımda çalıştıracağı analiz kuralı:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_2.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Gelişmiş Trafik Yönlendirme (Advanced Routing)

### A. Üst Bilgi (Header) Tabanlı Yönlendirme

Belirli kullanıcıları (örneğin sadece şirket içi test ekibini) her zaman yeni sürüme (Canary) yönlendirmek için Ingress veya Service Mesh üzerinde kural kurgulanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_3.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Geliştirici testi:

```bash
curl -H "X-Canary-User: true" https://api.company.com/v1/payment
```

### B. Trafik Aynalama (Traffic Mirroring / Shadow Traffic)

Yeni sürümü canlı kullanıcıları etkilemeden test etmenin en güvenli yolu **Traffic Mirroring**'dir. Istio VirtualService yardımıyla, canlı trafiğin bir kopyası arka planda sessizce Canary pod'larına gönderilir, ancak Canary'nin verdiği yanıtlar kullanıcıya iletilmez (sıfır risk).

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_4.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Argo Rollouts: Blue-Green Stratejisi

Blue-Green modelinde, yeni sürüm (Green) arka planda tamamen ayağa kalktıktan sonra, ön izleme (preview) servisi üzerinden manuel test edilebilir. Onay verilince aktif (live) servis yönlendirilir.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_5.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Doğrulama ve onay komutları:

```bash
# 1. Preview (Green) ortamı test edin:
curl https://preview-api.company.com/healthz

# 2. Testler başarılı ise geçişi onaylayın (Promote):
kubectl argo rollouts promote payment-bluegreen -n production
```

---

## 5. Flagger ve Gateway API ile Otomatik Canary (Modern Standart)

FluxCD ekosisteminde kullanılan **Flagger**, Kubernetes'in modern standardı olan **Gateway API**'yi kullanarak trafiği otomatik yönlendirir.

### Flagger `Canary` Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_6.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_6.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Kod Düzeyinde Özellik Bayrakları (Feature Flags - Flagsmith)

Progresif dağıtım altyapı düzeyinde yapılırken, kod düzeyinde de **Feature Flags** (Flagsmith vb.) kullanılarak bir özellik (Örn: Yeni sepet tasarımı) deploy yapılmadan anlık olarak açılıp kapatılabilir.

### Python Flagsmith Entegrasyonu

```python
import os
from flagsmith import Flagsmith

# Flagsmith istemcisini başlatın
flagsmith_client = Flagsmith(environment_key=os.environ["FLAGSMIH_ENV_KEY"])

def process_checkout(user_id: str):
    # Kullanıcıya ait özellikleri (flags) çekin
    user_flags = flagsmith_client.get_identity_flags(user_id)

    # Özelliğin aktif olup olmadığını kontrol edin
    if user_flags.is_feature_enabled("new-payment-engine"):
        return execute_new_payment_flow(user_id) # Canary kullanıcı grubu
    else:
        return execute_legacy_payment_flow(user_id)
```

---

## 7. A/B Testing (Istio VirtualService & Cookie-Based Routing)

A/B Testing, kullanıcıları tarayıcı çerezlerine (cookie) veya HTTP başlıklarına göre belirli gruplara (A ve B grupları) bölerek iki sürümün davranışını ölçer.

### Istio Cookie Tabanlı Yönlendirme

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [asamali_teslimat_progressive_delivery_manifest_7.yaml](../Manifests/09_gitops/asamali_teslimat_progressive_delivery_manifest_7.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
