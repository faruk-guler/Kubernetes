# Flux v2 ile GitOps Toolkit ve Sürekli Dağıtım

**Flux v2**, CNCF (Cloud Native Computing Foundation) bünyesinde bulunan kararlı (graduated) aşamadaki bir GitOps projesidir. ArgoCD ile birlikte 2026 yılının en yaygın kullanılan iki GitOps aracı arasında yer alır. Bildirimsel (declarative), çekme tabanlı (pull-based) modeli, Kubernetes-native bileşen mimarisi ve çoklu kiracılık (multi-tenancy) desteğiyle özellikle mikroservis sayısı yüksek kurumsal organizasyonlarda tercih edilir.

---

## 1. Flux v2 ve ArgoCD Karşılaştırması

| Kriter | ArgoCD | Flux v2 |
| :--- | :---: | :---: |
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

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/stefanprodan/podinfo
  ref:
    branch: master
```

### B. Kustomization (Deploy Yapılandırması)

Git reposundaki hangi klasörün hangi isim alanına (namespace) deploy edileceğini belirler:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  path: "./kustomize"
  prune: true # Git'ten silinen dosyaları Kubernetes'ten de siler
  sourceRef:
    kind: GitRepository
    name: podinfo
  targetNamespace: default
```

### C. HelmRelease (Helm Dağıtım Tanımı)

Dış kaynaklı bir Helm chart'ını Flux yardımıyla GitOps akışına dahil etmek için:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: podinfo
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: podinfo
      version: ">=6.0.0 <7.0.0"
      sourceRef:
        kind: HelmRepository
        name: podinfo
        namespace: flux-system
  values:
    replicaCount: 2
```

---

## 4. Çoklu Kiracılık (Multi-Tenancy) İzolasyonu

Flux'ta, farklı ekiplerin sadece kendi isim alanlarında (namespace) deploy yapabilmelerini sağlamak ve diğer ekiplerin kaynaklarını değiştirmelerini engellemek amacıyla `Kustomization` nesnesine ekibe özel bir **ServiceAccount** zımbalanabilir:

```yaml
# Kustomization nesnesine kısıtlı ServiceAccount bağlanması:
spec:
  serviceAccountName: backend-deployer-sa # Bu rol sadece backend ad alanına erişebilir
  targetNamespace: backend
```

---

## 5. Image Automation (Otomatik İmaj Güncelleme ve Git'e Push)

Flux'un en güçlü yeteneklerinden biri, imaj kayıt defterini (registry) izleyerek yeni bir docker etiketi çıktığında Git reposundaki YAML dosyasını **otomatik güncelleyip (git commit & push)** podları yenilemesidir:

```text
[Registry] ──► (ImageRepository) ──► (ImagePolicy: SemVer) ──► (ImageUpdateAutomation) ──► [Git Commit & Push]
```

### `ImageUpdateAutomation` Tanımı

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: podinfo-updater
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: podinfo
  git:
    commit:
      author: { name: fluxcdbot, email: fluxcdbot@users.noreply.github.com }
      messageTemplate: 'chore(image): bump to {{range .Updated.Images}}{{println .}}{{end}}'
    push: { branch: main }
  update:
    path: ./kustomize
    strategy: Setters
```

---

## 6. Notification Controller (Slack / Teams Bildirimleri)

Flux üzerinde bir senkronizasyon hatası olduğunda veya imaj güncellendiğinde Slack üzerinden uyarılmak için:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta2
kind: Alert
metadata:
  name: slack-alert
  namespace: flux-system
spec:
  providerRef: { name: slack-provider }
  eventSeverity: error
  eventSources:
    - { kind: Kustomization, name: '*' }
---
apiVersion: notification.toolkit.fluxcd.io/v1beta2
kind: Provider
metadata:
  name: slack-provider
  namespace: flux-system
spec:
  type: slack
  channel: 'production-alerts'
  secretRef: { name: slack-webhook-url }
```

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
