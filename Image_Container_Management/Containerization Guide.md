# Containerization (Konteynerleştirme) Rehberi

Kubernetes yolculuğumuzun ilk ve en kritik adımı, uygulamamızı bir konteyner imajı (container image) haline getirmektir. Kubernetes, kendi başına kodunuzu alıp çalıştırmaz; sadece konteynerleri orkestre eder. Bu nedenle, yazılan Dockerfile'ın kalitesi doğrudan Kubernetes cluster'ınızın güvenliğini, hızını, kaynak tüketimini ve ölçeklenme performansını etkiler.

İyi yazılmış bir Dockerfile sadece çalışan bir imaj değil; küçük, güvenli, hızlı açılan ve katman önbelleği (layer cache) optimize edilmiş bir artefakt üretmelidir.

---

## 1. Katman Önbelleği (Layer Caching) Mantığı

Docker, bir imajı inşa ederken (build) her satırdaki talimatı bir **katman (layer)** olarak yazar. Bir katman değişmediği sürece Docker bir sonraki derlemede önbellekten (cache) okur ve saniyeler içinde derleme tamamlanır. Ancak üstteki bir katman değiştiğinde, altındaki tüm katmanların önbelleği geçersiz kılınır ve baştan çalıştırılır.

* **Hatalı Sıralama:** Eğer kaynak kodumuzu bağımlılıklardan (dependencies) önce kopyalarsak, kodda yaptığımız tek bir karakterlik değişiklik bile tüm bağımlılıkların (npm install, pip install, go mod download vb.) internetten tekrar indirilmesine yol açar.
* **Doğru Sıralama:** Önce sadece bağımlılık listesini (örneğin `package.json` veya `go.mod`) kopyalayıp yüklemeyi çalıştırmalı, ardından kaynak kodumuzu kopyalamalıyız. Böylece bağımlılıklar değişmedikçe bu adım önbellekten anında geçecektir.

---

## 2. Multi-Stage Build (Çok Aşamalı Derleme)

Bir Go, Java veya TypeScript uygulamasını derlemek için derleyicilere, SDK'lara ve paket yöneticilerine ihtiyacımız vardır. Ancak bu araçların uygulamayı çalıştırmak için production ortamına gitmesine gerek yoktur. Örneğin bir Go compiler ~800MB yer kaplar ama ürettiği binary sadece 10MB'tır.

* **Anti-pattern (Tek Aşamalı):** Tüm derleme araçlarının son imajda kalması imaj boyutunu devasa hale getirir ve içinde terminal/paket yöneticisi barındırdığı için büyük güvenlik açıkları (saldırı yüzeyi) oluşturur.
* **Çözüm (Multi-stage):** Derleme işini "builder" adı verilen geçici bir aşamada tamamlayıp, nihai (runtime) aşamada sadece derlenmiş dosyaları (binary, build klasörü vb.) çok temiz ve minimal bir base imaj içine kopyalamaktır.

### Multi-Stage Build Karşılaştırması (Go Örneği)

```dockerfile
# ❌ KÖTÜ: Go derleyicisi production imajına giriyor
FROM golang:1.22
WORKDIR /app
COPY . .
RUN go build -o server .
CMD ["./server"]
# İmaj boyutu: ~900MB

# ✅ İYİ: Multi-stage — Sadece binary production'a gidiyor
# AŞAMA 1: Derleme Aşaması (Builder)
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server .

# AŞAMA 2: Çalıştırma Aşaması (Runtime)
FROM scratch
COPY --from=builder /app/server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8080
USER 65534
ENTRYPOINT ["/server"]
# İmaj boyutu: ~8MB (Sadece binary ve SSL sertifikaları)
```

---

## 3. Dil Bazında Optimize Dockerfile Şablonları

### Go ve Distroless Kullanımı

Go uygulamaları için en güvenli yaklaşım shell dahi barındırmayan Google'ın **distroless** imajlarını kullanmaktır:

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
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

### Python (Slim Base ve Non-Root)

Python uygulamalarında gereksiz derleme araçlarını içermeyen `slim` imajlar tercih edilmelidir. Paket yüklemeleri için `pip --no-cache-dir` kullanılmalıdır:

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
ENV PYTHONUNBUFFERED=1
EXPOSE 8000
USER 1000:1000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:application"]
```

### Node.js (Production Dependencies)

Node.js'te production aşamasında sadece `devDependencies` olmayan asıl bağımlılıkları yüklemek için `npm ci --only=production` kullanılır:

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
EXPOSE 3000
CMD ["node", "server.js"]
```

### Java (Spring Boot Layered Jar)

Java uygulamalarında container'ın bellek limitlerini JVM'e bildirmek için `UseContainerSupport` parametresi eklenmelidir:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN ./mvnw dependency:go-offline
COPY src ./src
RUN ./mvnw package -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring
COPY --from=builder /app/target/app.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-jar", "app.jar"]
```

---

## 4. .dockerignore Dosyası

Dockerfile ile aynı dizinde bulunması gereken `.dockerignore`, yerel bilgisayarınızdaki gereksiz veya gizli dosyaların Docker daemon'a gönderilmesini engelleyerek hem build süresini kısaltır hem de güvenliği artırır:

```dockerignore
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
vendor/
```

---

## 5. Güvenlik Kontrol Listesi (Security Checklist)

* **Root Olmayan Kullanıcı (Non-Root User):** Container içindeki uygulamayı asla `root` olarak çalıştırmayın. Olası bir container escape (konteynerden host'a sızma) durumunda saldırgan ana makinenin de root yetkisine sahip olur. Dockerfile sonuna mutlaka `USER 1000:1000` veya benzeri bir non-root kullanıcı tanımı ekleyin.
* **Sabit Versiyon Etiketleri (Pinning Tags):** `FROM base:latest` kullanmayın. `latest` etiketi her an değişebilir ve uygulamanızın localde çalışırken canlı ortamda (production) çökmesine yol açabilir. Her zaman `golang:1.22.3-alpine` gibi tam sürüm belirtin.
* **Gizli Bilgilerin Korunması:** API anahtarlarını, şifreleri Dockerfile içine `ENV` veya `ARG` olarak gömmeyin. İmaj geçmişini inceleyen herkes bu şifreleri görebilir. Derleme sırasında gizli bilgi gerekiyorsa `--mount=type=secret` kullanın.

---

## 6. Trivy ile Güvenlik Taraması

Oluşturduğumuz imajlardaki donanımsal kütüphane ve bağımlılık açıklarını (CVE) bulmak için Trivy kullanılır:

```bash
# Yerel bir imajı kritik ve yüksek açıklara karşı tarama
trivy image my-app:v1 --severity HIGH,CRITICAL

# Sürekli tarama için cluster içerisine Trivy Operator kurulumu
helm install trivy-operator aquasecurity/trivy-operator \
  --namespace trivy-system \
  --create-namespace
```
