# Multi-Architecture Image Build

2026'da ARM işlemciler her yerde: Apple Silicon (M1/M2/M3), AWS Graviton, Azure Ampere. Kubernetes cluster'ları artık sıklıkla karma mimari (amd64 + arm64) node'lardan oluşuyor. Image'larını çok mimari destekleyecek şekilde build etmek zorunlu hale geldi.

---

## Neden Multi-Arch?

```
Senaryo:
  MacBook M3 (arm64) → Local test ✅
  CI/CD sunucusu (amd64) → Build ✅
  EKS Graviton node (arm64) → Deploy ❌ (Image yanlış mimari!)

Çözüm: Tek tag, çoklu mimari
  ghcr.io/company/api:v1  →  amd64 için farklı layer
                          →  arm64 için farklı layer
  K8s doğru olanı otomatik çeker.
```

---

## Docker Buildx ile Multi-Arch Build

```bash
# Buildx builder oluştur (QEMU emülasyon destekli)
docker buildx create --name multi-arch-builder \
  --driver docker-container \
  --platform linux/amd64,linux/arm64 \
  --use

# Builder başlat
docker buildx inspect --bootstrap

# Multi-arch image build + push (tek komut)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ghcr.io/company/api:v2.1.0 \
  --tag ghcr.io/company/api:latest \
  --push \
  .

# Manifest kontrol et
docker buildx imagetools inspect ghcr.io/company/api:v2.1.0
# Image Details:
#   ghcr.io/company/api:v2.1.0
#   MediaType: application/vnd.oci.image.index.v1+json
#   Platforms:
#     linux/amd64
#     linux/arm64
```

---

## GitHub Actions ile Multi-Arch CI/CD

```yaml
name: Build & Push Multi-Arch Image

on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - uses: actions/checkout@v4

    - name: Docker meta (tag stratejisi)
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ghcr.io/${{ github.repository }}
        tags: |
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
          type=sha,prefix=sha-

    - name: Set up QEMU (arm64 emülasyonu)
      uses: docker/setup-qemu-action@v3
      with:
        platforms: linux/amd64,linux/arm64

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to GHCR
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha           # GitHub Actions cache
        cache-to: type=gha,mode=max
```

---

## Dockerfile'da Mimari Farkındalığı

```dockerfile
# TARGETPLATFORM — build sırasında otomatik set edilir
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder

ARG TARGETARCH    # amd64 veya arm64
ARG TARGETOS      # linux

WORKDIR /app
COPY . .
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-w -s" -o server .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

```dockerfile
# Platform bazlı farklı base image
FROM --platform=$TARGETPLATFORM python:3.12-slim

# Mimari'ye özel paket kurulumu
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      apt-get install -y libgomp1; \
    fi
```

---

## Node Mimarisine Göre Pod Yönlendirme

```yaml
# Sadece arm64 node'lara deploy et
spec:
  nodeSelector:
    kubernetes.io/arch: arm64

# veya affinity ile
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/arch
          operator: In
          values: [arm64]

# Karma cluster — multi-arch image → K8s doğrusunu seçer
# nodeSelector gereksiz, image manifest'i halleder
```

---

## Build Performansı: Native vs QEMU

```
QEMU emülasyon:
  amd64 makinede arm64 build → ~5-10x yavaş
  Küçük image'lar için kabul edilebilir

Native build (önerilen production için):
  amd64 runner + arm64 runner → paralel build
  GitHub Actions self-hosted runner veya AWS Graviton runner kullan
```

```yaml
# GitHub Actions: Native multi-arch (QEMU olmadan)
jobs:
  build-amd64:
    runs-on: ubuntu-latest        # amd64 native
    steps:
    - uses: docker/build-push-action@v5
      with:
        platforms: linux/amd64
        outputs: type=image,push=true,name=ghcr.io/company/api:amd64

  build-arm64:
    runs-on: ubuntu-24.04-arm     # arm64 native runner
    steps:
    - uses: docker/build-push-action@v5
      with:
        platforms: linux/arm64
        outputs: type=image,push=true,name=ghcr.io/company/api:arm64

  merge-manifest:
    needs: [build-amd64, build-arm64]
    runs-on: ubuntu-latest
    steps:
    - name: Merge manifests
      run: |
        docker buildx imagetools create \
          -t ghcr.io/company/api:v2.1.0 \
          ghcr.io/company/api:amd64 \
          ghcr.io/company/api:arm64
```

> [!TIP]
> AWS EKS Graviton node'ları (`t4g`, `m7g`) amd64'e göre %40 daha ucuz ve genellikle daha iyi güç verimliliği sunar. Multi-arch image build maliyeti, Graviton üzerindeki tasarrufla hızla geri kazanılır.
