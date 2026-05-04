# Flux v2 — GitOps Toolkit

Flux, CNCF'nin graduated projesi ve ArgoCD ile birlikte 2026'nın en yaygın GitOps aracı. Pull-based model, multi-tenancy desteği ve Kubernetes-native tasarımıyla özellikle büyük organizasyonlarda tercih ediliyor.

---

## Flux vs ArgoCD — Temel Fark

```
ArgoCD:
  Merkezi UI + Application CRD
  "ArgoCD bilir, deploy eder"
  Güçlü görselleştirme
  Tek kontrol noktası

Flux:
  UI yok (varsayılan) — Grafana/Weave GitOps ile eklenebilir
  GitRepository + Kustomization + HelmRelease CRD'leri
  "Git kaynak, Flux sadece sync eder"
  Multi-tenant, dağıtık yapı
  Terraform, Helm, Kustomize — hepsini yönetir
```

**Ne zaman Flux?**
- Çok sayıda ekip, çok sayıda repo
- ArgoCD'nin UI'ı şart değilse
- Flux CLI (flux) ile terminal odaklı çalışma
- Notification Controller ile Slack/Teams/webhook entegrasyonu

**Ne zaman ArgoCD?**
- Güçlü UI/dashboard isteniyor
- Tek merkezi GitOps server
- ApplicationSet ile çok sayıda uygulama

---

## Kurulum

```bash
# Flux CLI kurulumu
curl -s https://fluxcd.io/install.sh | sudo bash
# veya
brew install fluxcd/tap/flux

# Ön kontrol — cluster hazır mı?
flux check --pre

# GitHub'a bootstrap (Flux'u cluster'a kur + repo oluştur)
flux bootstrap github \
  --owner=company \
  --repository=k8s-gitops \
  --branch=main \
  --path=clusters/production \
  --personal=false \
  --token-auth

# GitLab'a bootstrap
flux bootstrap gitlab \
  --owner=company \
  --repository=k8s-gitops \
  --branch=main \
  --path=clusters/production \
  --token=$GITLAB_TOKEN
```

---

## Temel CRD'ler

### GitRepository — Kaynak Tanımı

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: k8s-apps
  namespace: flux-system
spec:
  interval: 1m              # Her 1 dakika Git'i kontrol et
  url: https://github.com/company/k8s-apps
  ref:
    branch: main
  secretRef:
    name: github-credentials  # GitHub token veya SSH key

---
apiVersion: v1
kind: Secret
metadata:
  name: github-credentials
  namespace: flux-system
type: Opaque
stringData:
  username: git
  password: ghp_xxxxxxxxxxxx   # GitHub PAT
```

### Kustomization — Deploy Tanımı

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: production-apps
  namespace: flux-system
spec:
  interval: 5m              # Her 5 dakika sync et
  retryInterval: 1m         # Hata durumunda 1 dk'da tekrar dene
  timeout: 3m               # Sync timeout
  sourceRef:
    kind: GitRepository
    name: k8s-apps
  path: ./apps/production   # Repo içindeki klasör
  prune: true               # Git'ten silinen objeleri cluster'dan da sil
  force: false              # Immutable field değişirse sil-yeniden-oluştur
  wait: true                # Tüm kaynaklar ready olana kadar bekle
  healthChecks:
  - apiVersion: apps/v1
    kind: Deployment
    name: api
    namespace: production
  patches:
  - patch: |
      - op: replace
        path: /spec/replicas
        value: 5
    target:
      kind: Deployment
      name: api
```

### HelmRelease — Helm Chart Deploy

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus-stack
  namespace: monitoring
spec:
  interval: 30m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: ">=55.0.0 <60.0.0"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    grafana:
      enabled: true
      adminPassword: ${GRAFANA_PASSWORD}  # Flux variable substitution
    prometheus:
      prometheusSpec:
        retention: 15d
  valuesFrom:
  - kind: Secret
    name: prometheus-secrets
    valuesKey: values.yaml
  install:
    crds: CreateReplace
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
```

```yaml
# HelmRepository — chart kaynağı
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 30m
  url: https://prometheus-community.github.io/helm-charts
```

---

## Multi-Tenancy

```yaml
# Her ekip kendi namespace'inde, kendi GitRepository'si
# flux-system: platform ekibi (tüm yetkilere sahip)
# team-alpha: sadece kendi namespace'ini yönetir

# Team Alpha ServiceAccount (sınırlı yetki)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-reconciler
  namespace: team-alpha
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: flux-reconciler
  namespace: team-alpha
subjects:
- kind: ServiceAccount
  name: flux-reconciler
  namespace: team-alpha
roleRef:
  kind: ClusterRole
  name: cluster-admin    # Sadece bu namespace'te
  apiGroup: rbac.authorization.k8s.io

---
# Team Alpha kendi Kustomization'ını yönetir
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: team-alpha-apps
  namespace: team-alpha
spec:
  serviceAccountName: flux-reconciler   # Sınırlı SA ile çalış
  sourceRef:
    kind: GitRepository
    name: team-alpha-repo
    namespace: team-alpha
  path: ./apps
  prune: true
```

---

## Image Automation (Otomatik Image Güncelleme)

Yeni image push edildiğinde Flux otomatik olarak Git'i günceller:

```yaml
# ImageRepository — hangi image'ı izle?
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: api-image
  namespace: flux-system
spec:
  image: ghcr.io/company/api
  interval: 5m
  secretRef:
    name: ghcr-credentials

---
# ImagePolicy — hangi tag'i seç?
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: api-policy
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: api-image
  policy:
    semver:
      range: ">=1.0.0 <2.0.0"    # SemVer aralığı
    # veya:
    # alphabetical:
    #   order: asc                 # En son tag

---
# ImageUpdateAutomation — Git'i güncelle
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata:
  name: api-automation
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: k8s-apps
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: flux@company.com
        name: Flux Bot
      messageTemplate: "ci: bump api to {{range .Updated.Images}}{{.}}{{end}}"
    push:
      branch: main
  update:
    strategy: Setters
    path: ./apps/production
```

```yaml
# Deployment'ta marker ekle — Flux bu satırı günceller
containers:
- name: api
  image: ghcr.io/company/api:v1.2.3 # {"$imagepolicy": "flux-system:api-policy"}
```

---

## Flux CLI Komutları

```bash
# Sync durumu
flux get all -n flux-system
flux get kustomizations -A
flux get helmreleases -A

# Hemen sync tetikle
flux reconcile kustomization production-apps
flux reconcile helmrelease prometheus-stack -n monitoring

# Kaynağı güncelle (git pull)
flux reconcile source git k8s-apps

# Sorun gider
flux logs --level=error
flux logs --kind=Kustomization --name=production-apps

# Kustomization suspend/resume
flux suspend kustomization production-apps
flux resume kustomization production-apps

# Tüm Flux bileşenlerini güncelle
flux install --version=latest
```

---

## Notification Controller

```yaml
# Slack bildirimi
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  secretRef:
    name: slack-webhook    # SLACK_WEBHOOK_URL

---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: deployment-alerts
  namespace: flux-system
spec:
  summary: "Production cluster"
  providerRef:
    name: slack
  eventSeverity: info
  eventSources:
  - kind: Kustomization
    name: "*"             # Tüm Kustomization'lar
  - kind: HelmRelease
    name: "*"
  exclusionList:
  - ".*no changes.*"      # Değişiklik yoksa bildirme
```
