# Helm OCI Registry

Helm v3.8'den itibaren chart'ları OCI (Open Container Initiative) registry'sine push edebilirsiniz. Artık `helm repo add` zorunlu değil — aynı registry hem container image'ı hem Helm chart'ı barındırır.

---

## OCI Chart vs Geleneksel Helm Repo

```
Geleneksel (index.yaml tabanlı):
  helm repo add myrepo https://charts.example.com
  helm install myapp myrepo/myapp --version 1.2.0

OCI (2026 standardı):
  helm install myapp oci://ghcr.io/company/charts/myapp --version 1.2.0
  # Repo eklemeye gerek yok — doğrudan pull
```

**OCI'nin avantajları:**
- Tek registry: image + chart birlikte
- Cosign ile chart imzalama
- Granüler erişim kontrolü (RBAC, registry auth)
- Immutable tag semantiği

---

## Chart Push & Pull

```bash
# Önce registry'ye login
helm registry login ghcr.io \
  --username $GITHUB_ACTOR \
  --password $GITHUB_TOKEN

# Chart'ı package'la
helm package ./mychart
# mychart-1.2.0.tgz oluşur

# OCI registry'e push
helm push mychart-1.2.0.tgz oci://ghcr.io/company/charts

# Pull (yerel cache'e)
helm pull oci://ghcr.io/company/charts/mychart --version 1.2.0

# Doğrudan install (pull olmadan)
helm install myapp oci://ghcr.io/company/charts/mychart \
  --version 1.2.0 \
  --namespace production \
  --create-namespace \
  -f values-production.yaml
```

---

## GitHub Actions — Build & Push Pipeline

```yaml
name: Helm Chart CI

on:
  push:
    paths:
    - 'charts/**'
    tags:
    - 'chart-v*'

jobs:
  publish-chart:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - uses: actions/checkout@v4

    - name: Helm kurulumu
      uses: azure/setup-helm@v4
      with:
        version: '3.16.x'

    - name: Chart lint
      run: helm lint ./charts/myapp

    - name: Chart test (unit)
      run: |
        helm plugin install https://github.com/helm-unittest/helm-unittest
        helm unittest ./charts/myapp

    - name: Chart version al
      id: version
      run: |
        VERSION=$(grep '^version:' charts/myapp/Chart.yaml | awk '{print $2}')
        echo "version=$VERSION" >> $GITHUB_OUTPUT

    - name: Package & Push
      run: |
        echo "${{ secrets.GITHUB_TOKEN }}" | \
          helm registry login ghcr.io --username ${{ github.actor }} --password-stdin
        helm package ./charts/myapp
        helm push myapp-${{ steps.version.outputs.version }}.tgz \
          oci://ghcr.io/${{ github.repository_owner }}/charts

    - name: Cosign ile Chart İmzala
      uses: sigstore/cosign-installer@v3
    - run: |
        cosign sign --yes \
          ghcr.io/${{ github.repository_owner }}/charts/myapp:${{ steps.version.outputs.version }}
```

---

## ArgoCD ile OCI Chart

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  source:
    repoURL: oci://ghcr.io/company/charts
    chart: myapp
    targetRevision: 1.2.0
    helm:
      valueFiles:
      - values-production.yaml
      values: |
        replicaCount: 3
        image:
          tag: v2.1.0
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## FluxCD ile OCI Chart

```yaml
# HelmRepository — OCI türünde
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: company-charts
  namespace: flux-system
spec:
  type: oci                                          # OCI modu
  url: oci://ghcr.io/company/charts
  interval: 10m
  secretRef:
    name: ghcr-credentials    # imagePullSecret formatında

---
# HelmRelease
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
  namespace: production
spec:
  interval: 10m
  chart:
    spec:
      chart: myapp
      version: ">=1.2.0 <2.0.0"    # Semver range
      sourceRef:
        kind: HelmRepository
        name: company-charts
        namespace: flux-system
  values:
    replicaCount: 3
```

---

## Chart Güvenliği — Cosign ile Doğrulama

```bash
# Chart imzasını doğrula (push sırasında imzalandıysa)
cosign verify \
  --certificate-identity-regexp "https://github.com/company/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/company/charts/myapp:1.2.0

# Chart SBOM doğrula
cosign verify-attestation \
  --type spdx \
  ghcr.io/company/charts/myapp:1.2.0
```

---

## Pratik Komutlar

```bash
# Registry'deki chart'ları listele
helm search repo oci://ghcr.io/company/charts    # (Henüz desteklenmez)
# Alternatif: ORAS CLI ile
oras repo ls ghcr.io/company/charts

# Chart bilgisi
helm show chart oci://ghcr.io/company/charts/myapp --version 1.2.0
helm show values oci://ghcr.io/company/charts/myapp --version 1.2.0

# Belirli versiyon geçmişi
oras manifest fetch ghcr.io/company/charts/myapp:1.2.0

# Local cache temizle
helm cache clean
ls ~/.cache/helm/registry/
```

> [!NOTE]
> OCI registry'ye push edilen chart'lar **immutable**'dır — aynı version tag'ini tekrar push edemezsiniz (GitHub Container Registry'de). Bu bir özellik: üretimde hangi versiyonun ne içerdiği garantili olur.
