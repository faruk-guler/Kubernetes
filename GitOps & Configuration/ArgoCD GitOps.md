# ArgoCD ile GitOps

2026 yılında cluster yönetimi = Git reposu yönetimi. Cluster üzerindeki her şeyin bir Git reposunda tanımlı olduğu bu yaklaşıma **GitOps** diyoruz.

## GitOps Neden Zorunludur?

| Sorun | GitOps Çözümü |
|:---|:---|
| "Kim ne değiştirdi?" | Git commit geçmişi = tam audit log |
| Cluster felakete uğradı | ArgoCD + repo = dakikalar içinde geri dönüş |
| Biri manuel kubectl yaptı | ArgoCD fark eder, Git'e döndürür (Drift Detection) |
| QA/Prod ortam farkı | Her ortam için ayrı Git branch/dizin |

## ArgoCD Kurulumu

```bash
# Namespace oluşturma
kubectl create namespace argocd

# ArgoCD kurulumu (stable branch)
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD CLI kurulumu
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Başlangıç admin şifresi
argocd admin initial-password -n argocd

# ArgoCD UI'ya erişim (port forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080 → admin / <yukarıdaki şifre>
```

> [!TIP]
> Production'da ArgoCD UI'ya erişim için `kubectl port-forward` yerine **Gateway API** veya bir LoadBalancer servisi kullanın. Bölüm 3'teki Gateway API entegrasyonuna bakın.

## App-of-Apps Paterni

Tüm altyapıyı (Cilium, Monitoring, ArgoCD'nin kendisi) tek bir "root app" üzerinden yönetin:

```yaml
# Root Application — tüm uygulamalar bu repo'dan izlenir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/k8s-infra.git
    targetRevision: HEAD
    path: apps/                  # Bu dizindeki tüm Application YAML'ları izlenir
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true                # Git'ten silinenleri cluster'dan da sil
      selfHeal: true             # Manuel değişiklikleri geri al
    syncOptions:
    - CreateNamespace=true
```

## Ortam Yönetimi (Multi-env)

```
k8s-infra-repo/
├── apps/
│   ├── dev/
│   │   ├── web-app.yaml
│   │   └── api-service.yaml
│   ├── staging/
│   │   └── web-app.yaml
│   └── production/
│       └── web-app.yaml
└── base/
    └── web-app-deployment.yaml
```

Her ortam için ayrı Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-app-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/k8s-infra.git
    targetRevision: main
    path: apps/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## ApplicationSet — Çoklu Cluster Dağıtımı

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: web-app-multicluster
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: europe
        url: https://europe-cluster.example.com
      - cluster: asia
        url: https://asia-cluster.example.com
  template:
    metadata:
      name: '{{cluster}}-web-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/my-org/k8s-infra.git
        targetRevision: HEAD
        path: apps/production
      destination:
        server: '{{url}}'
        namespace: production
```

## Kustomize vs Helm

2026 standartlarında:

| Araç | Ne Zaman? |
|:---|:---|
| **Helm** | Üçüncü parti uygulamalar (ArgoCD, Cilium, Prometheus) |
| **Kustomize** | Kendi geliştirdiğimiz uygulamalar, ortam bazlı özelleştirme |

ArgoCD her ikisini de yerel olarak destekler — harici bir tool gerektirmez.
