# ArgoCD ApplicationSet

Tek bir uygulama için `Application` CRD yeterlidir. Ama 50 cluster'a aynı uygulamayı deploy etmek ya da bir monorepo'daki her servisi ayrı Application olarak yönetmek gerektiğinde **ApplicationSet** devreye girer.

---

## ApplicationSet Nedir?

```
Application:     1 uygulama → 1 cluster
ApplicationSet:  1 şablon  → N uygulama (otomatik üretilir)
```

ApplicationSet Controller, Generator'dan aldığı verileri Application şablonuna uygulayarak Application'ları dinamik oluşturur, günceller ve siler.

---

## List Generator — Manuel Liste

En basit generator. Sabit bir liste üzerinden Application üretir:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook-list
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: staging
        url: https://staging-k8s.company.com
        env: staging
      - cluster: production-eu
        url: https://prod-eu.company.com
        env: production
      - cluster: production-us
        url: https://prod-us.company.com
        env: production

  template:
    metadata:
      name: "guestbook-{{cluster}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/company/gitops
        targetRevision: HEAD
        path: "apps/guestbook/overlays/{{env}}"
      destination:
        server: "{{url}}"
        namespace: guestbook
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

---

## Cluster Generator — Tüm Kayıtlı Cluster'lar

ArgoCD'ye kayıtlı tüm cluster'lara otomatik deploy:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          env: production    # Sadece production cluster'ları
      values:
        revision: "main"

  template:
    metadata:
      name: "cluster-addons-{{name}}"
    spec:
      project: platform
      source:
        repoURL: https://github.com/company/platform-addons
        targetRevision: "{{values.revision}}"
        path: addons/
      destination:
        server: "{{server}}"
        namespace: kube-system
      syncPolicy:
        automated:
          prune: false       # Cluster addon'larını silme!
          selfHeal: true
```

---

## Git Generator — Repo Dizin Yapısından

Git'teki dizin yapısına göre Application üretir. Monorepo için ideal:

```
gitops-repo/
├── apps/
│   ├── frontend/     ← Bir Application
│   ├── backend/      ← Bir Application
│   ├── worker/       ← Bir Application
│   └── scheduler/    ← Bir Application
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-from-git
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/company/gitops
      revision: HEAD
      directories:
      - path: "apps/*"         # apps/ altındaki her dizin
      - path: "apps/legacy"    # Bu dizini hariç tut
        exclude: true

  template:
    metadata:
      name: "{{path.basename}}"    # Dizin adı → Application adı
      annotations:
        notifications.argoproj.io/subscribe.on-sync-failed.slack: "#alerts"
    spec:
      project: default
      source:
        repoURL: https://github.com/company/gitops
        targetRevision: HEAD
        path: "{{path}}"           # Dizin yolu → kaynak path
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
```

### Git Files Generator — JSON/YAML'dan Parametre

```yaml
# Her app dizininde config.json varsa:
# apps/frontend/config.json → {"env": "prod", "replicas": 5}

generators:
- git:
    repoURL: https://github.com/company/gitops
    revision: HEAD
    files:
    - path: "apps/**/config.json"
```

---

## Matrix Generator — İki Generator'ı Çarpraz

Cluster listesi × uygulama listesi kombinasyonu:

```yaml
spec:
  generators:
  - matrix:
      generators:
      # Generator 1: Tüm cluster'lar
      - clusters:
          selector:
            matchLabels:
              env: production

      # Generator 2: Deploy edilecek uygulamalar
      - list:
          elements:
          - app: frontend
            version: "v2.1.0"
          - app: backend
            version: "v3.0.1"
```

Her cluster × her uygulama kombinasyonu için Application oluşturulur.

---

## Progressive Sync (Sync Waves)

Önce staging, sonra production — ApplicationSet ile dalgalı rollout:

```yaml
template:
  metadata:
    name: "myapp-{{cluster}}"
    annotations:
      argocd.argoproj.io/sync-wave: "{{syncWave}}"

generators:
- list:
    elements:
    - cluster: staging
      syncWave: "0"     # Önce
    - cluster: prod-eu
      syncWave: "1"     # Staging başarılıysa
    - cluster: prod-us
      syncWave: "2"     # En son
```

---

## Policy — Otomatik Silme Kontrolü

```yaml
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true    # ApplicationSet silinince Application'ları koru

  # Application silme politikası
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  strategy:
    type: RollingSync          # Hepsini aynı anda değil, sırayla sync et
    rollingSync:
      steps:
      - matchExpressions:
        - key: env
          operator: In
          values: [staging]
      - matchExpressions:
        - key: env
          operator: In
          values: [production]
```

---

## Debug

```bash
# ApplicationSet'leri listele
kubectl get applicationset -n argocd

# Oluşturulan Application'ları gör
kubectl get applications -n argocd | grep myapp

# ApplicationSet event'leri
kubectl describe applicationset apps-from-git -n argocd

# Generator sonuçlarını simüle et (dry-run benzeri)
argocd appset generate apps-from-git.yaml
```

> [!TIP]
> Git Generator ile monorepo yönetimi, her servisi ayrı Application olarak elle tanımlamaktan çok daha ölçeklenebilirdir. Yeni bir servis dizini oluşturunca ArgoCD otomatik olarak Application oluşturur.
