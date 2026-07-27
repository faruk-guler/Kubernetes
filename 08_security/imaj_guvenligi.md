# Konteyner İmaj Güvenliği En İyi Pratikleri (Container Image Security)

Kubernetes altyapısının güvenliği, üzerinde çalışan konteyner imajlarının güvenliği ile doğrudan ilişkilidir. Güvensiz, gereksiz araçlar barındıran veya root yetkileriyle çalışan imajlar, siber saldırganlar için sisteme giriş kapısı oluşturur. Bu dokümanda; deterministik etiketler, çok aşamalı derlemeler (multi-stage builds), root olmayan kullanıcılar, JVM bellek yönetimi ve imaj tarama pratiklerini ele alacağız.

---

## 1. Deterministik İmaj Etiketleri ve SHA256 Kullanımı

İmaj tanımlamalarında `latest` veya `v1` gibi değişken (mutable) etiketlerin kullanılması, her derlemede farklı bir imaj sürümünün çekilmesine yol açarak tutarsızlıklara ve güvenlik açıklarına neden olur.

Bunun yerine, imajın benzersiz kriptografik özetini (**SHA256 digest**) veya tam sürüm etiketlerini kullanmalıyız:

* ❌ **Güvensiz:** `FROM node:latest` veya `FROM openjdk:11`
* ▲ **Daha İyi:** `FROM node:20.11.0-alpine`
* 🟢 **En Güvenli:** `FROM maven:3.6.3-jdk-11-slim@sha256:68ce1cd457891f48d1e137c7d6a4493f60843e84c9e2634e3df1d3d5b381d36c`

---

## 2. Çok Aşamalı Derleme (Multi-Stage Builds) Kullanımı

Uygulamanın derleme (build) aşamasında kullanılan derleyiciler, SDK'lar ve paket yöneticileri (Maven, Gradle, npm vb.) çalışma zamanında (runtime) gereksizdir ve saldırı yüzeyini genişletir. **Çok aşamalı derleme** kullanarak derleme araçlarını ilk aşamada bırakıp, sadece nihai paketi (JAR, WAR, JS derlemesi vb.) küçük bir çalışma zamanı imajına taşımalıyız.

### Örnek Java Çok Aşamalı Dockerfile

```dockerfile
# 1. Aşama: Derleme (Build)
FROM maven:3.8.4-openjdk-17-slim AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

# 2. Aşama: Çalışma Zamanı (Runtime)
FROM gcr.io/distroless/java17-debian11@sha256:d8c0... AS runtime
WORKDIR /app
# Sadece üretilen JAR dosyasını kopyalıyoruz
COPY --from=builder /app/target/my-application.jar app.jar
USER 10001:10001
CMD ["app.jar"]
```

> [!TIP]
> **Distroless İmajlar:** Google tarafından sağlanan *distroless* imajlar, içinde paket yöneticisi, kabuk (shell - bash/sh) ve standart Linux araçları barındırmaz. Sadece uygulamanızın çalışması için gereken minimum çalışma zamanını (JRE, Node, Python vb.) içerir. Bu sayede siber saldırgan sızsa bile çalıştırabileceği bir shell bulamaz.

---

## 3. PID 1 Problemi ve Tini / Dumb-init Kullanımı

Linux'ta PID 1 (Process ID 1) olan ilk süreç, zombi süreçleri temizlemekten ve kernel sinyallerini (`SIGTERM`, `SIGINT`) alt süreçlere iletmekten sorumludur. Ancak Java, Node.js veya Python gibi uygulama süreçleri doğrudan PID 1 olarak çalıştırıldığında bu sinyalleri yakalayamaz ve Kubernetes pod'u kapatmak istediğinde `SIGTERM` sinyaline yanıt vermez. Bu durum podun 30 saniye boyunca asılı kalmasına ve sonunda zorla sonlandırılmasına (`SIGKILL`) yol açar.

Bu sorunu çözmek için hafif bir init sistemi olan **tini** veya **dumb-init** kullanılmalıdır:

```dockerfile
FROM alpine:3.19
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]
# Uygulamayı tini arkasında çalıştırın
CMD ["node", "app.js"]
```

---

## 4. Root Olmayan Kullanıcı (Non-Root User) Kullanımı

Varsayılan olarak Dockerfile içinde bir kullanıcı belirtilmezse, konteyner `root` (UID 0) yetkileriyle çalışır. Konteyner içindeki root kullanıcısı, sunucu (node) üzerindeki root kullanıcısı ile aynı haklara sahip olabilir.

Her zaman imaj içinde özel bir kullanıcı grubu oluşturup yetkileri sınırlandırmalıyız:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
# Standart olmayan bir kullanıcı oluşturup ona geçin
USER 1000:1000
CMD ["node", "app.js"]
```

---

## 5. JVM Uygulamalarında Kubernetes Kaynak Uyumsuzluğu

Eski Java/JVM sürümleri (Java 8u191 öncesi), konteyner içinde çalıştırıldıklarını anlamazlar. Sunucu üzerindeki tüm işlemci çekirdeklerini ve RAM miktarını kendilerine ait sanarak bellek taşması (Out-Of-Memory - OOM) nedeniyle Kubernetes tarafından aniden öldürülürler (**OOMKilled**).

### Çözüm

1. Her zaman **Java 10+** veya **Java 8 update 191+** üzeri modern JVM sürümlerini kullanın.
2. Konteyner bellek limitlerine uyum sağlaması için şu parametreleri uygulamanın başlangıç komutuna ekleyin:

```bash
java -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -jar application.jar
```

*`-XX:MaxRAMPercentage=75.0`* parametresi, JVM'in pod için tanımlanan RAM limitinin (örneğin 1GB) en fazla %75'ini (750MB) Heap memory olarak kullanmasını sağlar. Geri kalan %25 ise JVM'in diğer süreçleri ve işletim sistemi için bırakılır.

---

## 6. Google Jib ile Docker Daemon Olmadan İmaj Derleme

Java ekosisteminde Dockerfile yazmadan, localinizde Docker kurulu olmasına gerek kalmadan ve doğrudan Maven/Gradle üzerinden en iyi pratiklere uygun imajlar üretmek için Google Jib eklentisini kullanabilirsiniz. Jib, root olmayan kullanıcılar ve en iyi katmanlama (layering) stratejileriyle otomatik olarak imaj oluşturur.

### Maven `pom.xml` Yapılandırması

```xml
<plugin>
    <groupId>com.google.cloud.tools</groupId>
    <artifactId>jib-maven-plugin</artifactId>
    <version>3.4.0</version>
    <configuration>
        <to>
            <image>registry.company.com/apps/secure-java-app:v1.0</image>
        </to>
        <container>
            <user>10001:10001</user> <!-- Root olmayan kullanıcı tanımlaması -->
            <ports>
                <port>8080</port>
            </ports>
            <jvmFlags>
                <jvmFlag>-XX:+UseContainerSupport</jvmFlag>
                <jvmFlag>-XX:MaxRAMPercentage=75.0</jvmFlag>
            </jvmFlags>
        </container>
    </configuration>
</plugin>
```

Derlemek için:

```bash
# Doğrudan registry'e push etmek için:
mvn compile jib:build

# Local Docker daemon'a göndermek için:
mvn compile jib:dockerBuild
```

---

## 7. Node.js ve Python için İmaj Güvenliği

### Node.js En İyi Pratikleri

* Konteyner sınırlarına uyum sağlaması için Node.js uygulamalarında maksimum bellek limitini belirtin:

    `node --max-old-space-size=450 app.js` (512MB RAM limiti olan bir pod için).

* Geliştirme bağımlılıklarını (`devDependencies`) üretime taşımayın:

    `npm install --only=production` veya `npm ci --omit=dev` kullanın.

* Alpine tabanlı imajlarda varsayılan olarak gelen `node` kullanıcısını aktif edin:

    Dockerfile içine `USER node` ekleyin.

### Python En İyi Pratikleri

* Gereksiz gcc/make bağımlılıklarını çalışma zamanından temizlemek için `virtualenv` kullanarak çok aşamalı derleme yapın:

```dockerfile
# 1. Derleme Aşaması
FROM python:3.11-slim AS builder
WORKDIR /app
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2. Çalışma Zamanı Aşaması
FROM python:3.11-slim AS runtime
COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY . .
ENV PATH="/opt/venv/bin:$PATH"
USER 10001:10001
CMD ["python", "main.py"]
```

* Derleme sırasında `.pyc` dosyalarının oluşmasını önlemek ve buffer'ı kapatıp logların anlık çıkmasını sağlamak için şu çevre değişkenlerini ayarlayın:

    `ENV PYTHONDONTWRITEBYTECODE=1` ve `ENV PYTHONUNBUFFERED=1`

---

## 8. .dockerignore Kullanımı

`.git`, local test dosyaları, gizli şifreler (`.env`) ve derleme klasörleri (`target/`, `node_modules/`) imaj katmanlarına yanlışlıkla dahil edilmemelidir. Dockerfile ile aynı dizinde bir `.dockerignore` dosyası oluşturularak bu dosyalar dışlanmalıdır:

```
.git
.gitignore
node_modules
target
*.log
.env
Dockerfile
```
