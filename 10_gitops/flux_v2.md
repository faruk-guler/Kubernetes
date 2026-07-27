# Flux v2 ile GitOps Toolkit ve Sürekli Dağıtım

**Flux v2**, CNCF (Cloud Native Computing Foundation) bünyesinde bulunan kararlı (graduated) aşamadaki bir GitOps projesidir. ArgoCD ile birlikte 2026 yılının en yaygın kullanılan iki GitOps aracı arasında yer alır. Bildirimsel (declarative), çekme tabanlı (pull-based) modeli, Kubernetes-native bileşen mimarisi ve çoklu kiracılık (multi-tenancy) desteğiyle özellikle mikroservis sayısı yüksek kurumsal organizasyonlarda tercih edilir.

---

## 1. Flux v2 ve ArgoCD Karşılaştırması

| Kriter | ArgoCD | Flux v2 |
|:---|:---:|:---:|
| **Kullanıcı Arayüzü (UI)** | ✅ Yerleşik ve Çok Güçlü | ❌ Varsayılan olarak yok (Weave GitOps ile eklenebilir) |
| **Mimari** | Tek bir merkezi sunucu | Dağıtık, mikro-operatör yapısı (GitOps Toolkit) |
| **Yapılandırma Modeli** | Merkezi Application nesnesi | GitRepository, Kustomization, HelmRelease |
| **Operasyon Tarzı** | UI ve ArgoCD CLI odaklı | Git commit ve Flux CLI odaklı |
| **Gelişmiş Özellikler** | ApplicationSet ile şablonlama | Otomatik imaj güncelleme (Image Automation) |

---

## 2. Kurulum ve Git Bootstrap Adımları

Flux v2, kümedeki kurulumunu ve Git deposundaki entegrasyonu tek bir komutla (**bootstrap**) otomatik olarak gerçekleştirir.

```bash
# 1. Flux CLI Kurulumu (Linux)
curl -s https://fluxcd.io/install.sh | sudo bash

# 2. Kümenin kuruluma uygun olduğunu denetleyin
flux check --pre

# 3. GitHub Bootstrap (Flux'u kümede kurar ve kodları Git deposunda başlatır)
flux bootstrap github \
  --owner=my-company \
  --repository=k8s-gitops-infra \
  --branch=main \
  --path=clusters/production \
  --personal=false \
  --token-auth
```

Bu işlem bittikten sonra Flux, kümede kendi podlarını çalıştırır ve sizin GitHub reponuzda `/clusters/production` klasöründe kendi konfigurasyon dosyalarını oluşturup push eder. Artık kümede yapılacak her şey sadece Git reposuna commit eklenerek yönetilir.

---

## 3. Temel Flux v2 CRD Yapılandırmaları

Flux, GitOps Toolkit mimarisini oluşturan modüler CRD kaynakları ile çalışır.

### A. GitRepository (Kaynak Depo Tanımı)

Hangi Git reposunun hangi sıklıkla taranacağını ve kimlik bilgilerini (sertifika/token) tanımlar:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [flux_v2_manifest_2.yaml](../Manifests/09_gitops/flux_v2_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Kustomization (Deploy Yapılandırması)

Git reposundaki hangi klasörün hangi isim alanına (namespace) deploy edileceğini belirler:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [flux_v2_manifest_3.yaml](../Manifests/09_gitops/flux_v2_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. HelmRelease (Helm Dağıtım Tanımı)

Dış kaynaklı bir Helm chart'ını Flux yardımıyla GitOps akışına dahil etmek için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [flux_v2_manifest_4.yaml](../Manifests/09_gitops/flux_v2_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Çoklu Kiracılık (Multi-Tenancy) İzolasyonu

Flux'ta, farklı ekiplerin sadece kendi isim alanlarında (namespace) deploy yapabilmelerini sağlamak ve diğer ekiplerin kaynaklarını değiştirmelerini engellemek amacıyla `Kustomization` nesnesine ekibe özel bir **ServiceAccount** zımbalanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [flux_v2_manifest_5.yaml](../Manifests/09_gitops/flux_v2_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Image Automation (Otomatik İmaj Güncelleme ve Git'e Push)

Flux'un en benzersiz yeteneklerinden biri, imaj kayıt defterini (registry) izleyerek yeni bir docker imaj etiketi (tag) çıktığında, Git reposundaki YAML dosyasındaki sürüm bilgisini **otomatik güncelleyip (git commit & push)** podları yenilemesidir.

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [flux_v2_manifest_1.yaml](../Manifests/09_gitops/flux_v2_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Notification Controller (Slack / Teams Bildirimleri)

Flux üzerinde bir senkronizasyon hatası olduğunda veya imaj güncellendiğinde Slack üzerinden uyarılmak için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [flux_v2_manifest_6.yaml](../Manifests/09_gitops/flux_v2_manifest_6.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. Temel Flux CLI Yönetim Komutları

```bash
# 1. Tüm Flux bileşenlerinin ve senkronizasyonların genel durumunu görün
flux get all -A

# 2. Git reposundaki bir Kustomization güncellemesini anında tetikleyin (Reconcile)
flux reconcile kustomization deploy-production-apps --with-source

# 3. Canlı hata günlüklerini (logs) filtreleyerek okuyun
flux logs --level=error

# 4. GitOps akışını geçici olarak durdurma (Suspend) ve tekrar açma (Resume)
# Not: Manuel acil müdahalelerde Flux'un değişikliklerinizi ezmesini engellemek için suspend edebilirsiniz.
flux suspend kustomization deploy-production-apps
flux resume kustomization deploy-production-apps
```
