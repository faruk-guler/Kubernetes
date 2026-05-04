# Distroless & Minimal Images — OCI Artifacts

Güvenli ve küçük container image'ları sadece CVE azaltmakla kalmaz — build süresi, registry bandwidth ve pull süresi de düşer. **Distroless** ve **Chainguard** images 2026'da production standardıdır.

---

## Neden Minimal Image?

```bash
# Ubuntu tabanlı tipik image
ubuntu:22.04        → 77 MB, ~200+ paket, ~180 CVE

# Distroless — sadece uygulama + runtime
gcr.io/distroless/java21-debian12  → 85 MB, ~5 paket, ~0 CVE

# Scratch — tamamen boş (statik binary için)
scratch             → 0 MB, 0 paket, 0 CVE
```

---

## Distroless Images (Google)

Distroless image'lar: shell yok, package manager yok, sadece uygulama ve runtime kütüphaneleri.

```dockerfile
# Go — statik binary + distroless nonroot
FROM golang:1.23 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

```dockerfile
# Python — distroless python
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

FROM gcr.io/distroless/python3-debian12
COPY --from=builder /install /usr/local
COPY . /app
WORKDIR /app
CMD ["app.py"]
```

```dockerfile
# Java 21 — distroless JRE
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app
COPY . .
RUN ./mvnw package -DskipTests
RUN jlink --strip-debug --no-header-files --no-man-pages \
    --add-modules java.base,java.logging,java.sql \
    --output /custom-jre

FROM gcr.io/distroless/java-base-debian12:nonroot
COPY --from=builder /custom-jre /opt/jre
COPY --from=builder /app/target/app.jar /app.jar
ENV PATH="/opt/jre/bin:$PATH"
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

**Mevcut distroless image'lar:**

| Image | Kullanım |
|:------|:---------|
| `distroless/static-debian12` | Statik Go/Rust binary |
| `distroless/base-debian12` | glibc gerektiren binary'ler |
| `distroless/python3-debian12` | Python uygulamaları |
| `distroless/java21-debian12` | Java 21 runtime |
| `distroless/nodejs22-debian12` | Node.js 22 |
| `distroless/cc-debian12` | C/C++ uygulamaları |

---

## Chainguard Images — Sıfır CVE Garantisi

```dockerfile
# Chainguard — günlük build, en az paket, APK tabanlı
FROM cgr.dev/chainguard/go:1.23 AS builder
WORKDIR /app
COPY . .
RUN go build -ldflags="-w -s" -o server ./cmd/server

FROM cgr.dev/chainguard/static:latest-glibc
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

```bash
# Chainguard image'ları genellikle 0 CVE ile gelir
trivy image cgr.dev/chainguard/nginx:latest
# Total: 0 (UNKNOWN: 0, LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 0)

# Karşılaştırma
trivy image nginx:1.27-alpine
# Total: 18 (LOW: 8, MEDIUM: 6, HIGH: 3, CRITICAL: 1)
```

---

## Debug: Distroless'ta Ephemeral Container

Distroless'ta shell olmadığı için standart debug yapılamaz:

```bash
# Ephemeral debug container ekle (shell ile)
kubectl debug -it my-pod \
  --image=busybox:1.36 \
  --target=app \
  -- sh

# Veya debug image içeren özel ephemeral
kubectl debug -it my-pod \
  --image=gcr.io/distroless/base-debian12:debug \
  --target=app

# Process namespace paylaşarak debug
kubectl debug -it my-pod \
  --image=nicolaka/netshoot \
  --share-processes \
  -- bash
```

---

## OCI Artifacts — Registry'de Container Dışı İçerik

OCI v1.1 ile registry sadece container image değil, her türlü artifact'ı saklayabilir:

```
OCI Registry (ghcr.io)
  ├── container images
  ├── Helm charts
  ├── SBOM dosyaları
  ├── Cosign imzaları
  ├── OPA/Kyverno policy'leri
  ├── Terraform modülleri
  └── Wasm modülleri
```

### ORAS — OCI Registry As Storage

```bash
# ORAS kurulumu
curl -LO "https://github.com/oras-project/oras/releases/latest/download/oras_linux_amd64.tar.gz"
tar -zxf oras_linux_amd64.tar.gz -C /usr/local/bin oras

# ORAS ile herhangi bir dosyayı push et
oras push ghcr.io/company/configs/kyverno-policies:v1.0 \
  --artifact-type application/vnd.opa.policy.v1+rego \
  policies/deny-latest.rego

# Pull
oras pull ghcr.io/company/configs/kyverno-policies:v1.0 \
  -o ./downloaded-policies/

# Artifact içeriğini listele
oras manifest fetch ghcr.io/company/configs/kyverno-policies:v1.0 | jq .

# Registry'deki tüm artifact'ları listele
oras repo ls ghcr.io/company/configs
oras repo tags ghcr.io/company/configs/kyverno-policies
```

### OCI Policy Distribution — Kyverno

```bash
# Kyverno policy'lerini OCI'dan çek
kyverno apply oci://ghcr.io/company/policies:latest \
  --resource pod.yaml

# ArgoCD ile OCI artifact olarak policy deploy
# (Flux kustomize-controller OCI desteği)
```

---

## Multi-Stage Build Best Practices

```dockerfile
# Production-grade multi-stage pattern
FROM golang:1.23-alpine AS deps
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download && go mod verify

FROM deps AS builder
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -ldflags="-w -s -X main.version=${VERSION}" \
    -trimpath \
    -o /bin/server ./cmd/server

# Security scan aşaması (CI'da)
FROM builder AS scanner
RUN go install golang.org/x/vuln/cmd/govulncheck@latest && \
    govulncheck ./...

# Final image — minimal
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /bin/server /server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

---

## Boyut Karşılaştırması

| Base Image | Boyut | CVE (ortalama) | Shell |
|:-----------|------:|:--------------:|:-----:|
| `ubuntu:22.04` | 77 MB | ~180 | ✅ |
| `debian:12-slim` | 75 MB | ~40 | ✅ |
| `alpine:3.20` | 7 MB | ~5 | ✅ (ash) |
| `distroless/base` | 20 MB | ~2 | ❌ |
| `distroless/static` | 2 MB | 0 | ❌ |
| `chainguard/static` | 1 MB | 0 | ❌ |
| `scratch` | 0 MB | 0 | ❌ |

> [!WARNING]
> Distroless image'larda `/bin/sh` olmadığı için `ENTRYPOINT ["sh", "-c", "..."]` çalışmaz. Binary'yi doğrudan ENTRYPOINT olarak çağırın: `ENTRYPOINT ["/server"]`.
