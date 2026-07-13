# Konteynerleştirme Rehberi (Containerization Guide)

Kubernetes yolculuğumuzun ilk ve en kritik adımı, uygulamamızı bir konteyner imajı (container image) haline getirmektir. Kubernetes, kendi başına kodunuzu alıp derlemez veya çalıştırmaz; sadece konteynerleri orkestre eder. Bu nedenle, yazılan Dockerfile'ın kalitesi doğrudan Kubernetes kümenizin (cluster) güvenliğini, hızını, kaynak tüketimini ve ölçeklenme performansını etkiler.

İyi yazılmış bir Dockerfile sadece çalışan bir imaj değil; küçük, güvenli, hızlı açılan ve katman önbelleği (layer cache) optimize edilmiş bir artefakt üretmelidir.

---

## 1. Katman Önbelleği (Layer Caching) Mantığı

Docker, bir imajı inşa ederken (build) her satırdaki talimatı bir **katman (layer)** olarak yazar. Bir katman değişmediği sürece Docker bir sonraki derlemede önbellekten (cache) okur ve saniyeler içinde derleme tamamlanır. Ancak üstteki bir katman değiştiğinde, altındaki tüm katmanların önbelleği geçersiz kılınır ve baştan çalıştırılır.

* **Hatalı Sıralama (Anti-Pattern):** Eğer kaynak kodumuzu bağımlılıklardan (dependencies) önce kopyalarsak, kodda yaptığımız tek bir karakterlik değişiklik bile tüm bağımlılıkların (`npm install`, `pip install`, `go mod download` vb.) internetten tekrar indirilmesine yol açar.
* **Doğru Sıralama (Best Practice):** Önce sadece bağımlılık listesini (örneğin `package.json` veya `go.mod`) kopyalayıp bağımlılık kurulumunu çalıştırmalı, ardından kaynak kodumuzu kopyalamalıyız. Böylece bağımlılıklar değişmedikçe bu adım önbellekten anında geçecektir.

---

## 2. Multi-Stage Build (Çok Aşamalı Derleme)

Bir Go, Java veya TypeScript uygulamasını derlemek için derleyicilere, SDK'lara ve paket yöneticilerine ihtiyacımız vardır. Ancak bu araçların uygulamayı çalıştırmak için üretim (production) ortamına gitmesine gerek yoktur. Örneğin bir Go derleyicisi ~800MB yer kaplarken, ürettiği derlenmiş binary dosyası sadece 10-15MB'tır.

* **Tek Aşamalı Derleme (Anti-pattern):** Tüm derleme araçlarının son imajda kalması imaj boyutunu devasa hale getirir ve içinde terminal/paket yöneticisi barındırdığı için ciddi güvenlik açıkları oluşturur.
* **Çözüm (Multi-stage):** Derleme işini `builder` adı verilen geçici bir aşamada tamamlayıp, nihai (runtime) aşamada sadece derlenmiş dosyaları çok temiz ve minimal bir base imaj (örneğin alpine veya distroless) içine kopyalamaktır.

---

## 3. Dil Bazında Optimize Dockerfile Şablonları

### Go ve Distroless Kullanımı

Go uygulamaları için en güvenli yaklaşım shell dahi barındırmayan Google'ın **distroless** imajlarını kullanmaktır:

```dockerfile
# 1. Aşama: Derleme (Builder)
FROM golang:1.22-alpine AS builder
WORKDIR /app
# Bağımlılıkları önbelleğe al
COPY go.mod go.sum ./
RUN go mod download
# Kaynak kodu kopyala ve derle
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o main .

# 2. Aşama: Çalışma Zamanı (Runtime)
FROM gcr.io/distroless/static-debian12:latest-amd64
WORKDIR /
COPY --from=builder /app/main /main
USER 65532:65532
ENTRYPOINT ["/main"]
```

### Python (Slim Base ve Non-Root)

Python uygulamalarında gereksiz derleme araçlarını içermeyen `slim` imajlar tercih edilmelidir. Paket yüklemeleri için `pip --no-cache-dir` kullanılmalı ve root olmayan bir kullanıcı (`non-root`) oluşturulmalıdır:

```dockerfile
# 1. Aşama: Bağımlılık Derleme
FROM python:3.11-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# 2. Aşama: Çalışma Zamanı
FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
# Güvenlik için root olmayan kullanıcı
RUN useradd -u 1000 appuser && chown -R appuser /app
USER appuser
CMD ["python", "app.py"]
```

### Node.js (Production Dependencies)

Node.js'te production aşamasında sadece `devDependencies` olmayan asıl bağımlılıkları yüklemek için `npm ci --only=production` kullanılır:

```dockerfile
# 1. Aşama: Derleme
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# 2. Aşama: Çalışma Zamanı
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY --from=builder /app/dist ./dist
USER node
CMD ["node", "dist/index.js"]
```

### Java (Spring Boot Layered Jar)

Java uygulamalarında Spring Boot'un layered jar özelliğini kullanmak katman önbelleklemesini en üst seviyeye çıkarır:

```dockerfile
# 1. Aşama: Derleme
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvc dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# 2. Aşama: Çalışma Zamanı
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
# JVM bellek limitlerini konteynere göre ayarla
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

---

## 4. `.dockerignore` Dosyası

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

* **Root Olmayan Kullanıcı (Non-Root User):** Konteyner içindeki uygulamayı asla `root` olarak çalıştırmayın. Olası bir konteynerden sızma (`container escape`) durumunda saldırgan ana makinenin de root yetkisine sahip olur. Dockerfile sonuna mutlaka `USER 1000:1000` ekleyin.
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

---

## Özet

Konteyner imajını optimize etmek, Kubernetes üzerindeki uygulamanın hızını ve güvenliğini doğrudan belirler. **Multi-stage build** kullanımı imaj boyutunu küçültürken, **non-root** kullanıcı kullanımı ve **Trivy** entegrasyonu sisteminizin güvenlik açıklarını en aza indirir.
