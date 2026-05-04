# Kustomize ile Yapılandırma Yönetimi

**Kustomize**, Kubernetes manifest dosyalarını şablonlaştırmadan (templating) özelleştirmenize olanak tanıyan, bildirimsel (declarative) bir yapılandırma yönetimi aracıdır. Helm'in aksine ham YAML dosyalarını **patch** mantığıyla yönetir.

## Helm vs Kustomize — Ne Zaman Hangisi?

| Kriter | Helm | Kustomize |
|:---|:---:|:---:|
| Åablonlama | ✅ Güçlü | âŒ Yok |
| Harici bağımlılık | Gerekli | âŒ Yok (kubectl içinde) |
| Öğrenme eğrisi | Orta | Düşük |
| Üçüncü parti app | ✅ İdeal | ⚠️ Sınırlı |
| Kendi uygulamam | ⚠️ Aşırı karmaşık | ✅ İdeal |

## Kustomize Kurulumu

kubectl v1.14+ sürümüyle zaten gömülü gelir (`kubectl apply -k`). Standalone kurulum için:

```bash
# Standalone kurulum
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo install -o root -g root -m 0755 kustomize /usr/local/bin/kustomize

# Doğrulama
kustomize version
kubectl kustomize --help
```

## Proje Yapısı (Base & Overlays)

Kustomize'ın temel mimarisi `base` (tüm ortamlarda ortak) ve `overlays` (ortam-özgü değişiklikler) üzerine kuruludur:

```
my-app/
├── base/                        # Tüm ortamlarda ortak YAML
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/                     # Geliştirme ortamı
    │   ├── kustomization.yaml
    │   └── replica-patch.yaml   # replicas: 1
    ├── staging/                 # Staging ortamı
    │   └── kustomization.yaml
    └── prod/                    # Production ortamı
        ├── kustomization.yaml
        └── replica-patch.yaml   # replicas: 5
```

### base/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

commonLabels:
  app: my-web-app
  managed-by: kustomize
```

### overlays/prod/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

bases:
- ../../base

resources:
- namespace.yaml

patchesStrategicMerge:
- replica-patch.yaml      # replicas değerini override et
- resource-patch.yaml     # CPU/Memory limitlerini artır

images:
- name: my-app
  newTag: v2.1.0          # İmaj tag'ini override et

configMapGenerator:
- name: app-config
  literals:
  - LOG_LEVEL=warn
  - ENV=production
```

### overlays/prod/replica-patch.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-web-app
spec:
  replicas: 5
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "1Gi"
```

## Temel Komutlar

```bash
# YAML çıktısını önizle (cluster'a uygulamaz)
kustomize build overlays/prod
kubectl kustomize overlays/prod

# Cluster'a uygula
kubectl apply -k overlays/prod
kubectl apply -k overlays/dev

# Diff göster
kubectl diff -k overlays/prod
```

## JSON Patch ile Hassas Değişiklik

```yaml
# overlays/prod/kustomization.yaml içinde
patchesJson6902:
- target:
    group: apps
    version: v1
    kind: Deployment
    name: my-web-app
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/env/0/value
      value: "production"
    - op: add
      path: /spec/template/spec/nodeSelector
      value:
        environment: production
```

## ArgoCD ile Kustomize

ArgoCD Kustomize'ı natively destekler:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
spec:
  source:
    repoURL: https://github.com/my-org/my-app.git
    path: overlays/prod         # Kustomize dizinini göster
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

> [!TIP]
> Kustomize, karmaşık Helm chart'ları yönetmek istemeyen ve standart K8s YAML'larına sadık kalmak isteyen ekipler için en temiz çözümdür. `configMapGenerator` sayesinde ConfigMap değeri değiştiğinde pod otomatik olarak yeniden başlatılır.
