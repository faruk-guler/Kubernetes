# Konteyner İmaj Hazırlama ve Registry Yönetimi

## 1. Multi-Stage Dockerfile (2026 Best Practices)

Üretim imajları küçük ve güvenli olmalıdır. Multi-stage build ile build araçları son imajda yer almaz.

### Go Uygulaması

```dockerfile
# Stage 1: Build
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server ./cmd/server

# Stage 2: Minimal production image (distroless)
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/server"]
```

### Node.js Uygulaması

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER node
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

### Python Uygulaması

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
USER 1000
CMD ["python", "app.py"]
```

## 1.1 HashiCorp Packer ile Altın İmaj (Golden Image) Oluşturma
Konteynerlerin üzerinde koştuğu Node imajlarını (AMI, VMDK, ISO) otomatize etmek için kullanılır.
```hcl
source "amazon-ebs" "k8s" {
  ami_name = "k8s-node-{{timestamp}}"
  instance_type = "t3.medium"
}
build {
  sources = ["source.amazon-ebs.k8s"]
  provisioner "shell" {
    script = "./scripts/install-k8s.sh"
  }
}
```

## 1.2 Containerfile (Buildah/Podman)
`Dockerfile` ile aynı sözdizimine sahiptir ancak Buildah ve Podman ecosisteminde `Containerfile` isimlendirmesi tercih edilir.

## 2. Dockerfile Best Practices

| Kural | Açıklama |
|:---|:---|
| `distroless` veya `alpine` kullan | Saldırı yüzeyini minimize eder |
| `USER nonroot` ekle | Root olmayan kullanıcı ile çalıştır |
| `.dockerignore` oluştur | `.git`, `node_modules`, `*.test` dosyalarını hariç tut |
| `--no-cache` kullan | Gereksiz önbelleği engelle |
| Katmanları birleştir | Tek `RUN` ile birden fazla komut çalıştır |
| LABEL ekle | `LABEL org.opencontainers.image.version="1.0"` |

## 3. Buildah — Rootless Build

Docker daemon gerektirmeden imaj oluşturma:

```bash
# Kurulum
dnf install -y buildah   # RHEL/Fedora

# İmaj oluşturma
ctr=$(buildah from nginx:alpine)
buildah run $ctr -- apk add --no-cache curl
buildah config --label version=1.0 $ctr
buildah commit $ctr my-custom-nginx:v1.0
buildah push my-custom-nginx:v1.0 registry.example.com/my-custom-nginx:v1.0
buildah rm $ctr
```

## 4. Harbor — Kurumsal İmaj Registry

```bash
# Helm ile Harbor kurulumu
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --set expose.type=ingress \
  --set expose.tls.enabled=true \
  --set harborAdminPassword=MySecretPass \
  --set persistence.persistentVolumeClaim.registry.storageClass=longhorn

# Login
docker login registry.example.com -u admin -p MySecretPass

# Push
docker tag myapp:v1.0 registry.example.com/production/myapp:v1.0
docker push registry.example.com/production/myapp:v1.0
```

## 5. Kubernetes'te imagePullSecrets

Private registry'den imaj çekmek için:

```bash
# Registry secret oluştur
kubectl create secret docker-registry registry-credentials \
  --docker-server=registry.example.com \
  --docker-username=admin \
  --docker-password=MySecretPass \
  --docker-email=admin@example.com \
  -n production
```

```yaml
# Pod tanımına ekle
spec:
  imagePullSecrets:
  - name: registry-credentials
  containers:
  - name: app
    image: registry.example.com/production/myapp:v1.0
```

## 6. İmaj Güvenliği: Trivy ile Tarama

```bash
# Build sırasında tara
trivy image my-app:v1.0 --severity CRITICAL,HIGH

# GitHub Actions / CI entegrasyonu
# .github/workflows/security.yaml içinde:
- uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'my-app:${{ github.sha }}'
    format: 'sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'   # Kritik bulgu varsa pipeline'ı durdur
```

