# Supply Chain Security

Modern Kubernetes güvenliği sadece cluster içiyle bitmez — koddan üretim image'ına kadar her adımın güvenilir ve doğrulanabilir olması gerekir. Bu zincire "software supply chain" denir.

> [!NOTE]
> **Kapsam:** Bu dosya supply chain politikası, imzalama ve SLSA çerçevesini kapsar. Araç bazlı CVE tarama ve SBOM üretimi için `Image & Container Management/Image Scanning & SBOM.md` dosyasına bakın.

---

## Supply Chain Tehditleri

```
Geliştirici → Git → CI/CD → Registry → Kubernetes

Her adımda risk:
  ✗ Zararlı bağımlılık (npm, pip, Maven — SolarWinds tarzı saldırı)
  ✗ CI/CD pipeline'ına sızma (CodeCov breach 2021)
  ✗ Image manipülasyonu (registry'de push sonrası)
  ✗ İmzasız veya güvensiz image deploy
  ✗ Kötü amaçlı base image (Docker Hub'da yaygın)
  ✗ Compromised build environment
```

---

## SLSA Framework

Supply chain saldırılarına karşı Google tarafından geliştirilen 4 seviyeli güvence modeli:

| Seviye | Gereksinim | Ne Sağlar |
|:------:|:-----------|:----------|
| **SLSA 1** | Build süreci belgelenmiş | Provenance belgesi var |
| **SLSA 2** | Managed build servis (GitHub Actions vb.) | Kaynak → binary izlenebilir |
| **SLSA 3** | Kaynak + build tamlığı kanıtlanmış | Provenance doğrulanabilir |
| **SLSA 4** | İki kişilik onay + hermetic build | Tam yeniden üretilebilirlik |

```bash
# SLSA seviyenizi kontrol edin
slsa-verifier verify-image \
  ghcr.io/company/api:v1.2.0 \
  --source-uri github.com/company/api \
  --source-tag v1.2.0
```

---

## Sigstore & Cosign — Image İmzalama

```bash
# Cosign kurulumu (Linux)
curl -O -L https://github.com/sigstore/cosign/releases/download/v2.4.0/cosign-linux-amd64
install cosign-linux-amd64 /usr/local/bin/cosign

# Anahtar çifti oluştur (air-gapped ortamlar için)
cosign generate-key-pair
# cosign.key (özel — Secret olarak sakla) + cosign.pub (açık)

# Image imzala (push sonrası — digest ile imzala, tag değil)
IMAGE=ghcr.io/company/api@sha256:abc123...
cosign sign --key cosign.key $IMAGE

# İmzayı doğrula
cosign verify --key cosign.pub $IMAGE

# Keyless imzalama — CI/CD için önerilen (Fulcio CA + Rekor log)
cosign sign $IMAGE
# GitHub Actions'da otomatik OIDC token kullanır
# İmza Rekor transparency log'a kaydedilir → public audit trail
```

### GitHub Actions — Build, Scan & Sign Pipeline

```yaml
name: Build, Scan & Sign

on:
  push:
    tags: ['v*']

jobs:
  build-scan-sign:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write    # Keyless Cosign için OIDC token

    steps:
    - uses: actions/checkout@v4

    - name: Build & Push
      uses: docker/build-push-action@v6
      id: build
      with:
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        # Digest ile imzalama için output gerekli
        outputs: type=image,name=ghcr.io/${{ github.repository }},push-by-digest=true

    - name: Trivy CVE Tarama
      uses: aquasecurity/trivy-action@0.24.0
      with:
        image-ref: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        severity: CRITICAL,HIGH
        exit-code: 1    # CRITICAL varsa pipeline dur

    - name: Syft — SBOM Üret
      uses: anchore/sbom-action@v0
      with:
        image: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        format: spdx-json
        output-file: sbom.spdx.json

    - name: Cosign — Keyless İmzala & SBOM Akıtla
      uses: sigstore/cosign-installer@v3

    - run: |
        # Digest ile imzala (tag değişkenliğine karşı güvenli)
        cosign sign --yes \
          ghcr.io/${{ github.repository }}@${{ steps.build.outputs.digest }}
        # SBOM'u attestation olarak göm
        cosign attest --yes \
          --predicate sbom.spdx.json \
          --type spdx \
          ghcr.io/${{ github.repository }}@${{ steps.build.outputs.digest }}
```

---

## SLSA Provenance Üretimi

```yaml
# GitHub Actions — SLSA Level 3 provenance
jobs:
  build:
    outputs:
      hashes: ${{ steps.hash.outputs.hashes }}

  provenance:
    needs: build
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v1.10.0
    with:
      base64-subjects: ${{ needs.build.outputs.hashes }}
    permissions:
      actions: read
      id-token: write
      contents: write
```

---

## Kyverno — Kubernetes'te İmza & Policy Doğrulama

### İmzasız Image Engelleme

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  background: false
  rules:
  - name: check-image-signature
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: [production, staging]
    verifyImages:
    - imageReferences:
      - "ghcr.io/company/*"
      attestors:
      - count: 1
        entries:
        - keyless:
            subject: "https://github.com/company/*"
            issuer: "https://token.actions.githubusercontent.com"
            rekor:
              url: https://rekor.sigstore.dev
```

### Registry Kısıtlama & Latest Tag Yasağı

```yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registry
spec:
  validationFailureAction: Enforce
  rules:
  - name: allowed-registries
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Sadece ghcr.io/company veya registry.company.com kullanılabilir"
      pattern:
        spec:
          containers:
          - image: "ghcr.io/company/* | registry.company.com/*"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
  - name: no-latest
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "'latest' tag kullanılamaz — sabit versiyon (SHA veya semver) kullanın"
      pattern:
        spec:
          containers:
          - image: "!*:latest"
```

---

## Git Commit İmzalama

```bash
# SSH ile imzala (GitHub 2026 önerisi — GPG'den daha basit)
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true

# Commit'i doğrula
git log --show-signature

# GitHub'da "Verified" rozeti için SSH anahtarını
# Settings → SSH and GPG keys → Signing key olarak ekle
```

---

## Supply Chain Güvenliği Olgunluk Matrisi

| Katman | Başlangıç | Orta | İleri (2026) |
|:-------|:----------|:-----|:-------------|
| **Build** | GitHub Actions | Hermetic build | SLSA L3 provenance |
| **Image** | Sabit tag | Trivy tarama | Cosign keyless imza |
| **SBOM** | Yok | Syft üretim | Attestation + doğrulama |
| **Admission** | Yok | Registry kısıtlama | İmza doğrulama (Kyverno) |
| **Runtime** | Yok | Falco alerts | eBPF runtime policy |

> [!IMPORTANT]
> Supply chain güvenliği katmanlıdır: **İmzala (Cosign) → Tara (Trivy) → Belgele (SBOM/SLSA) → Doğrula (Kyverno) → İzle (Falco/Tetragon)** — her katman bir öncekinin zayıf noktasını kapatır.
