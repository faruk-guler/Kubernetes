# ArgoCD ile GitOps Tabanlı Sürekli Dağıtım (ArgoCD Guide)

Modern bulut mimarilerinde ve Kubernetes yönetiminde "Bunu terminalden `kubectl apply` ile ben kurmuştum" demek ciddi bir operasyonel risktir ve 2026 standartlarında bir anti-pattern'dir. Küme üzerindeki tüm bileşenlerin (altyapı araçları, uygulamalar vb.) bir Git deposu (Git Repository) içinde tanımlı olduğu ve kümenin durumunun Git ile otomatik senkronize edildiği bu yaklaşıma **GitOps** diyoruz. Bu yapının en popüler ve olgunlaşmış aracı ise **ArgoCD**'dir.

---

## 1. Neden GitOps Zorunludur?

| Operasyonel Sorun | GitOps ve ArgoCD Çözümü |
|:---|:---|
| **Denetim Eksikliği:** "Kümeyi kim, ne zaman değiştirdi?" | Git commit geçmişi = Değiştirilemez denetim kaydı (Audit Log). |
| **Felaket Kurtarma:** Küme çöktü veya silindi. | Git reposundaki tanımlar sayesinde yeni küme dakikalar içinde eski haline döner. |
| **Konfigürasyon Sapması (Drift):** Birisi elle `kubectl edit` yaptı. | ArgoCD bu sapmayı anında fark eder, uyarı üretir ve durumu Git'teki haline geri çeker (Self-Healing). |
| **Ortam Yönetimi:** Geliştirme (Dev) ve Canlı (Prod) farkları. | Her ortam için Git üzerinde ayrı klasörler veya branch'ler tanımlanır. |

---

## 2. ArgoCD Kurulumu ve Başlangıç Yapılandırması

ArgoCD bileşenlerini kümenizde kurmak ve arayüze erişmek için aşağıdaki adımları uygulayın:

```bash
# 1. ArgoCD için isim alanı oluşturun
kubectl create namespace argocd

# 2. Resmi stabil manifestoları uygulayarak kurulumu yapın
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. ArgoCD CLI Aracını Kurun (Linux)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# 4. Varsayılan geçici yönetici (admin) şifresini çözün
argocd admin initial-password -n argocd

# 5. Tarayıcıdan arayüze erişmek için port-forward başlatın
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Tarayıcıda https://localhost:8080 adresine gidin
# Kullanıcı adı: admin | Şifre: Yukarıdaki komutun çıktısı
```

> [!TIP]
> Üretim ortamlarında ArgoCD arayüzüne port-forward ile değil, güvenli bir Ingress veya **Gateway API** ile TLS şifreli erişim sağlanmalıdır.

---

## 3. App-of-Apps (Uygulamaların Uygulaması) Paterni

Büyük altyapılarda, kümedeki onlarca uygulamayı (Cilium, Monitoring, Cert-Manager vb.) ArgoCD arayüzünden tek tek eklemek yerine **App-of-Apps** deseni kullanılır. Bu desende, tek bir "Kök Uygulama (Root App)" oluşturulur ve bu kök uygulama Git üzerindeki diğer uygulamaların YAML tanımlarını okuyarak tüm kümeyi otomatik olarak ayağa kaldırır (bootstrap).

### Örnek Kök Uygulama YAML Tanımı (`root-app.yaml`)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_gitops_manifest_1.yaml](../Manifests/09_gitops/argocd_gitops_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Çoklu Ortam (Multi-Env) Yönetimi

Uygulamanın farklı ortamlara (Dev, Prod) farklı parametrelerle dağıtılması için Git dizin yapısı Kustomize veya Helm ile kurgulanır.

### Git Klasör Hiyerarşisi

```
my-app-gitops/
├── base/                           # Ortak Kubernetes tanımları
│   └── deployment.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml      # replicas: 1, env: DEV
    │   └── argocd-app-dev.yaml
    └── prod/
        ├── kustomization.yaml      # replicas: 5, env: PROD
        └── argocd-app-prod.yaml
```

### Prod Ortamı İçin ArgoCD Application Tanımı (`overlays/prod/argocd-app-prod.yaml`)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_gitops_manifest_2.yaml](../Manifests/09_gitops/argocd_gitops_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. ApplicationSet — Çoklu Küme Dağıtımı

Eğer birden fazla Kubernetes kümesini (Örn: AWS, Azure ve On-Premise) aynı anda yönetiyorsanız, tek tek Application yazmak yerine **ApplicationSet** kullanılır. ApplicationSet şablonları, belirlenen kriterlere göre (örneğin Git üzerindeki klasör isimleri veya etiketler) dinamik olarak yüzlerce ArgoCD Application nesnesini otomatik üretir.
*(Detaylı örnekler ve kurallar için bkz: [argocd_applicationset.md](argocd_applicationset.md))*

---

## 6. Kustomize ve Helm Seçimi

ArgoCD hem Helm'i hem de Kustomize'ı yerleşik olarak destekler:

* **Helm:** Genellikle kurumsal ve dış kaynaklı altyapı araçlarını (Prometheus, Cilium, Istio) kurmak için tercih edilir.
* **Kustomize:** Şirket içinde kendi yazdığınız mikroservisleri farklı ortamlara özelleştirerek (replica sayısı, env config) dağıtmak için en temiz çözümdür.
