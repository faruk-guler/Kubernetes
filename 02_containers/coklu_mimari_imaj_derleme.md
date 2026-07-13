# Çoklu Mimari İmaj Derleme (Multi-Architecture Image Build)

2026 yılı standartlarında ARM64 tabanlı işlemciler bulut altyapılarında ve yerel cihazlarda her yere yayılmıştır: Apple Silicon (M1/M2/M3/M4), AWS Graviton, Azure Ampere ve GCP Tau T2A.

Modern Kubernetes kümeleri artık sıklıkla karma mimariye sahip (örneğin hem `amd64/x86_64` hem de `arm64` işlemcili) düğümlerden oluşmaktadır. Bu nedenle, imajlarınızı her iki mimaride de sorunsuz çalışacak şekilde derlemek kurumsal bir zorunluluk haline gelmiştir.

---

## 1. Neden Çoklu Mimari (Multi-Arch)?

Karma mimarili bir Kubernetes kümesinde, bir geliştiricinin localinde ve canlı ortamda yaşayabileceği sorun şudur:

```
MacBook M4 (ARM64) ──► Lokal test başarılı ✅
CI/CD Sunucusu (AMD64) ──► İmaj derleme başarılı ✅
AWS EKS Graviton (ARM64) Düğümü ──► Dağıtım (Deploy) Başarısız ❌
                                    (Hata: "exec format error")
```

**Çözüm: Tek Etiket, Çoklu Mimari (Image Index)**
Kayıt defterine (registry) tek bir etiketle (`myapp:v1.0.0`) yükleme yapılır. Bu etiket, arka planda farklı mimariler için farklı katmanları (layers) işaret eden bir **OCI Image Index** (Manifest) yapısına sahiptir. Kubernetes pod'u ayağa kaldırırken, üzerinde koştuğu CPU mimarisine uygun olan katmanı registry'den otomatik olarak tespit edip çeker.

---

## 2. Docker Buildx ile Çoklu Mimari Derleme

Docker **Buildx** CLI eklentisi, arkasında `Moby BuildKit` motorunu kullanarak birden fazla mimariyi tek bir komutla derlememizi ve doğrudan kayıt defterine göndermemizi sağlar.

### Adım 1: QEMU Emülasyon Destekli Builder Oluşturma ve Seçme

```bash
# Çoklu platform desteğine sahip yeni bir builder oluşturun
docker buildx create --name multi-arch-builder \
  --driver docker-container \
  --platform linux/amd64,linux/arm64 \
  --use

# Builder'ı başlatın ve durumunu doğrulayın
docker buildx inspect --bootstrap
```

### Adım 2: İmajı Aynı Anda İki Platform İçin Derleyip Push Etme

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag registry.example.com/production/myapp:v1.0.0 \
  --tag registry.example.com/production/myapp:latest \
  --push \
  .
```

### Adım 3: Üretilen Manifest Yapısını İnceleme

Kayıt defterindeki imajın hangi mimarileri desteklediğini kontrol etmek için:

```bash
docker buildx imagetools inspect registry.example.com/production/myapp:v1.0.0
# Çıktı Özeti:
# MediaType: application/vnd.oci.image.index.v1+json
# Platforms:
#   - linux/amd64
#   - linux/arm64
```

---

## 3. Dockerfile İçinde Mimari Farkındalığı (Architecture Awareness)

Multi-stage build yaparken veya derleme komutlarında mimariye göre farklı binary indirmek istediğimizde, BuildKit tarafından sunulan otomatik değişkenleri (deklare edilerek) kullanabiliriz:

| Değişken Adı | Açıklama | Örnek Değer |
|:---|:---|:---|
| `BUILDPLATFORM` | Derlemenin yapıldığı ana makinenin mimarisi | `linux/amd64` |
| `TARGETPLATFORM` | İmajın derlendiği hedef platform | `linux/arm64` |
| `TARGETARCH` | İmajın derlendiği hedef CPU mimarisi | `arm64` |

### Örnek Dockerfile Kullanımı

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
WORKDIR /app
COPY . .
# Dockerfile içindeki hedef mimariye göre Go derleyicisine hedefi bildir
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -o main .

FROM alpine:3.19
WORKDIR /
COPY --from=builder /app/main /main
CMD ["/main"]
```

---

## 4. GitHub Actions ile Çoklu Mimari CI/CD Hattı

GitHub Actions üzerinde otomatik QEMU kurarak hem amd64 hem de arm64 imajlarını derleyip Harbor/DockerHub gibi bir yere push eden tam iş akışı (workflow):

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [coklu_mimari_imaj_derleme_manifest_1.yaml](../Manifests/02_containers/coklu_mimari_imaj_derleme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Kubernetes Üzerinde CPU Mimarisine Göre Pod Planlama

Bazı durumlarda uygulamanız sadece `amd64` uyumlu kütüphanelere bağımlıdır ve `arm64` düğümlerde çalışamaz. Bu durumda podların doğru işlemciye sahip düğümlere planlanmasını garanti etmek için **NodeSelector** kullanmalıyız:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [coklu_mimari_imaj_derleme_manifest_2.yaml](../Manifests/02_containers/coklu_mimari_imaj_derleme_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Build Performansı: QEMU vs. Native Runner

* **QEMU Emülasyonu (Kolay ama Yavaş):** `amd64` bir sunucu üzerinde `arm64` imaj derlemek için QEMU CPU emülasyonu kullanılır. Bu işlem normal derlemeye göre **5 ila 10 kat daha yavaş** sürer. Küçük projeler için kabul edilebilir ancak büyük derleme süreçlerinde pipeline süresini tıkar.
* **Native Paralel Derleme (Hızlı ve Önerilen):** Production ortamları için, CI/CD sisteminizde doğrudan ARM64 tabanlı self-hosted runner (örneğin AWS Graviton sanal sunucuları) veya paralel çalışan mimariye özel runner'lar konumlandırarak derleme süresini optimize etmelisiniz.

---

## Özet

Çoklu mimari (**Multi-arch**) desteği, modern bulut mimarisinde donanım maliyetlerini düşürmenin anahtarıdır. AWS Graviton gibi ARM64 tabanlı düğümler, geleneksel x86 sunucularına göre **%40'a varan fiyat/performans avantajı** sunar. **Docker Buildx** ve **QEMU** entegrasyonu ile imajlarınızı çoklu mimarili hale getirmek, bu tasarrufun kapısını sonuna kadar açar.
