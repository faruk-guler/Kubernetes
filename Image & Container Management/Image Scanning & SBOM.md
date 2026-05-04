# Image Scanning & SBOM — Supply Chain Güvenliği

2026'da bir imajı registry'e push etmek yetmez. **Ne içerdiğini**, **hangi CVE'leri barındırdığını** ve **içeriğin doğrulanabilir olduğunu** kanıtlamanız gerekir. Bu üç araç bu zinciri oluşturur:

- **Trivy / Grype** — CVE tarama
- **Syft** — SBOM (Software Bill of Materials) üretme
- **Cosign** — imzalama ve doğrulama

---

## Trivy — Kapsamlı Güvenlik Tarayıcı

Trivy; imaj, dosya sistemi, Git repo, Helm chart ve Kubernetes cluster'ı tarar.

```bash
# Kurulum
brew install aquasecurity/trivy/trivy    # macOS
# Linux:
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.57.0

# Temel imaj tarama
trivy image ghcr.io/company/api:v2.1.0

# Sadece CRITICAL ve HIGH
trivy image --severity CRITICAL,HIGH ghcr.io/company/api:v2.1.0

# JSON çıktı (CI entegrasyonu için)
trivy image --format json --output trivy-report.json ghcr.io/company/api:v2.1.0

# SARIF formatı (GitHub Security tab)
trivy image --format sarif --output trivy.sarif ghcr.io/company/api:v2.1.0
```

### Cluster Genelinde Sürekli Tarama (Trivy Operator)

```bash
helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/
helm install trivy-operator aquasecurity/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set trivy.ignoreUnfixed=true \
  --set operator.scanJobTimeout=5m
```

```bash
# Cluster'daki tüm zaafiyetleri listele
kubectl get vulnerabilityreports -A

# Belirli bir pod'un raporu
kubectl get vulnerabilityreports -n production \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.report.summary}{"\n"}{end}'

# Kritik zaafiyetleri filtrele
kubectl get vulnerabilityreports -A \
  -o jsonpath='{range .items[?(@.report.summary.criticalCount > 0)]}{.metadata.name}{"\n"}{end}'
```

---

## Grype — Hızlı Alternatif Tarayıcı

```bash
# Kurulum
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# İmaj tara
grype ghcr.io/company/api:v2.1.0

# Sadece kritik
grype ghcr.io/company/api:v2.1.0 --fail-on critical

# SBOM'dan tara (Syft ile oluşturulmuş)
grype sbom:./api-sbom.spdx.json
```

---

## Syft — SBOM Üretimi

SBOM (Software Bill of Materials), imajın içindeki tüm paket ve bağımlılıkların envanteri.

```bash
# Kurulum
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# SBOM üret (SPDX formatı — endüstri standardı)
syft ghcr.io/company/api:v2.1.0 -o spdx-json=api-sbom.spdx.json

# CycloneDX formatı
syft ghcr.io/company/api:v2.1.0 -o cyclonedx-json=api-sbom.cdx.json

# Dosya sistemi tarama (local build artifact)
syft dir:./dist -o spdx-json=dist-sbom.spdx.json

# SBOM'u imaj içine göm
syft ghcr.io/company/api:v2.1.0 -o spdx-json \
  | cosign attest --predicate - --type spdx ghcr.io/company/api:v2.1.0
```

---

## Cosign — İmaj İmzalama

```bash
# Kurulum
brew install sigstore/tap/cosign    # macOS
# Linux:
curl -O -L https://github.com/sigstore/cosign/releases/download/v2.4.0/cosign-linux-amd64
install cosign-linux-amd64 /usr/local/bin/cosign

# Anahtar çifti oluştur
cosign generate-key-pair

# İmajı imzala (OCI registry'e push edilmiş olmalı)
cosign sign --key cosign.key ghcr.io/company/api:v2.1.0

# Keyless imzalama (Sigstore — CI için önerilen)
# GitHub Actions'da OIDC token ile otomatik
cosign sign ghcr.io/company/api:v2.1.0    # COSIGN_EXPERIMENTAL=1 ile

# İmzayı doğrula
cosign verify \
  --key cosign.pub \
  ghcr.io/company/api:v2.1.0
```

---

## GitHub Actions — Tam Güvenli CI Pipeline

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
      id-token: write       # Keyless Cosign için

    steps:
    - uses: actions/checkout@v4

    - name: Build & Push
      uses: docker/build-push-action@v6
      with:
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

    - name: Trivy — CVE Tarama
      uses: aquasecurity/trivy-action@0.24.0
      with:
        image-ref: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        format: sarif
        output: trivy.sarif
        severity: CRITICAL,HIGH
        exit-code: 1    # CRITICAL varsa pipeline dur

    - name: GitHub Security Tab'a yükle
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: trivy.sarif

    - name: Syft — SBOM Üret
      uses: anchore/sbom-action@v0
      with:
        image: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        format: spdx-json
        output-file: sbom.spdx.json

    - name: Cosign — Keyless İmzala
      uses: sigstore/cosign-installer@v3

    - name: İmzala ve SBOM'u akıtla
      run: |
        cosign sign ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        cosign attest \
          --predicate sbom.spdx.json \
          --type spdx \
          ghcr.io/${{ github.repository }}:${{ github.ref_name }}
```

---

## Kyverno ile İmzalı İmaj Zorunluluğu

Cluster'a yalnızca imzalı imajların girmesini zorunlu kıl:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  validationFailureAction: Enforce
  rules:
  - name: verify-cosign-signature
    match:
      resources:
        kinds: [Pod]
    verifyImages:
    - imageReferences:
      - "ghcr.io/company/*"
      attestors:
      - entries:
        - keyless:
            subject: "https://github.com/company/*"
            issuer: "https://token.actions.githubusercontent.com"
            rekor:
              url: https://rekor.sigstore.dev
```

---

## Araç Seçim Özeti

| Araç | Görev | Ne Zaman? |
|:-----|:------|:----------|
| **Trivy** | CVE tarama | Her CI build + cluster sürekli tarama |
| **Trivy Operator** | Cluster geneli sürekli izleme | Daima kurulu olmalı |
| **Grype** | Alternatif CVE tarama | Trivy'ye ek cross-check |
| **Syft** | SBOM üretimi | Her release tag |
| **Cosign** | İmaj imzalama | Her production push |

> [!WARNING]
> `latest` tag'li imajlar Cosign ile imzalanamaz — her zaman sabit sürüm (SHA veya semver) kullanın. `cosign sign ghcr.io/company/api:latest` yapıldığında hangi imajın imzalandığı belirsizdir.
