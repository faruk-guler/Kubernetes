# Containerization Rehberi

Kubernetes yolculuğunun ilk adımı uygulamayı containerize etmektir. İyi yazılmış bir Dockerfile sadece çalışan bir image değil; küçük, güvenli, hızlı ve yeniden üretilebilir bir artefakt üretir.

---

## Dockerfile Temel Prensipleri

### Multi-Stage Build (Zorunlu)

```dockerfile
# ❌ Kötü: Tek aşamalı — Go derleyicisi production image'a giriyor
FROM golang:1.22
WORKDIR /app
COPY . .
RUN go build -o server .
CMD ["./server"]
# Image boyutu: ~900MB

# ✅ İyi: Multi-stage — sadece binary production'a gidiyor
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download                    # Bağımlılıkları önbelleğe al
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-w -s" \                 # Debug sembollerini çıkar
    -o server .

FROM scratch                           # Boş image — sadece binary
COPY --from=builder /app/server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8080
USER 65534                             # nobody user
ENTRYPOINT ["/server"]
# Image boyutu: ~8MB
```

---

## Dil Bazında En İyi Pratikler

### Go

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
# go.mod/sum önce kopyala → bağımlılık cache katmanı
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o /app/server ./cmd/server

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/server /server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

### Python

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
# Bağımlılıkları ayrı katmana al
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
# Sadece kurulmuş paketleri kopyala
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1
EXPOSE 8000
USER 1000:1000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:application"]
```

### Node.js

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production          # package-lock.json'dan tam yükle

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
EXPOSE 3000
CMD ["node", "server.js"]
```

### Java (Spring Boot)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN ./mvnw dependency:go-offline      # Bağımlılık cache
COPY src ./src
RUN ./mvnw package -DskipTests

# Spring Boot layered jar
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring
COPY --from=builder /app/target/app.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \       # Container memory limitini kullan
  "-XX:MaxRAMPercentage=75.0", \      # JVM heap = container limit × %75
  "-jar", "app.jar"]
```

---

## .dockerignore (Zorunlu)

```dockerignore
# .dockerignore — build context'e gönderilmeyecekler
.git
.gitignore
Dockerfile
*.md
*.log
node_modules/
__pycache__/
*.pyc
.env
.env.*
coverage/
dist/
build/
*.test.go
*_test.go
vendor/    # Go vendor varsa, go.sum yeterli
```

---

## Güvenlik Kontrol Listesi

```dockerfile
# ✅ 1. Root olmayan kullanıcı
USER 1000:1000

# ✅ 2. Minimal base image
FROM gcr.io/distroless/static-debian12   # Go için
FROM python:3.12-slim                     # Python için (değil python:3.12)

# ✅ 3. Sabit tag — latest KULLANMA
FROM golang:1.22.3-alpine               # ❌ golang:latest değil

# ✅ 4. Sır (secret) image'a girmesin
# ❌ Yanlış:
RUN curl -H "Authorization: Bearer $TOKEN" https://api.example.com/download
# ✅ Doğru: Build arg kullan
ARG GITHUB_TOKEN
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN=$(cat /run/secrets/github_token) \
    pip install git+https://...

# ✅ 5. HEALTHCHECK tanımla
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz || exit 1
```

---

## Image Boyutu Optimizasyonu

```bash
# Image katmanlarını analiz et
docker history my-app:v1 --human --format "{{.Size}}\t{{.CreatedBy}}"

# Dive aracı ile görsel analiz
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  wagoodman/dive:latest my-app:v1

# Boyutu küçültme teknikleri:
# 1. Multi-stage build
# 2. apt-get clean && rm -rf /var/lib/apt/lists/*
# 3. --no-install-recommends
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

---

## Container Registry & Image Signing

```bash
# GitHub Container Registry (GHCR)
docker build -t ghcr.io/company/my-app:sha-$(git rev-parse --short HEAD) .
docker push ghcr.io/company/my-app:sha-$(git rev-parse --short HEAD)

# Image imzalama (Cosign)
cosign sign --key cosign.key ghcr.io/company/my-app:sha-abc123

# Kubernetes'te imzalı image doğrulama (Kyverno)
kubectl apply -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  rules:
  - name: verify-cosign
    match:
      resources:
        kinds: [Pod]
    verifyImages:
    - imageReferences:
      - "ghcr.io/company/*"
      attestors:
      - entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              MFkwEwYHKoZIzj0CAQYIKB...
              -----END PUBLIC KEY-----
EOF
```

---

## Trivy ile Güvenlik Taraması

```bash
# Local image tarama
trivy image my-app:v1 --severity HIGH,CRITICAL

# CI/CD entegrasyonu (GitHub Actions)
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/company/my-app:${{ github.sha }}
    format: sarif
    severity: CRITICAL,HIGH
    exit-code: 1    # CRITICAL varsa pipeline başarısız

# Sürekli tarama (cluster'daki image'lar)
helm install trivy-operator aquasecurity/trivy-operator \
  --namespace trivy-system \
  --create-namespace
kubectl get vulnerabilityreports -A
```
