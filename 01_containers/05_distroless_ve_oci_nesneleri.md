# Distroless, Minimal İmajlar ve OCI Nesneleri (Distroless & OCI Artifacts)

Güvenli, küçük ve optimize edilmiş konteyner imajları kullanmak sadece güvenlik açıklarını (CVE) azaltmakla kalmaz; aynı zamanda imaj derleme süresini, kayıt defteri bant genişliğini ve Kubernetes'in imaj çekme (`image pull`) sürelerini de ciddi oranda düşürür. **Distroless** ve **Chainguard** imajları 2026 yılı standart üretim (production) ortamlarının varsayılanıdır.

---

## 1. Neden Minimal İmaj Tercih Etmeliyiz?

Geleneksel imajlar ile modern minimal imajlar arasındaki boyut ve güvenlik farkları şu şekildedir:

```
# Ubuntu tabanlı tipik imaj (Gereksiz araçlar dahil)
ubuntu:22.04         ──► 77 MB, ~200+ paket, ~180+ bilinen açık (CVE)

# Distroless (Sadece uygulama ve onun runtime bağımlılıkları)
distroless/java21    ──► 85 MB, ~5 paket, ~0 bilinen açık (CVE)

# Scratch (Tamamen boş imaj - sadece derlenmiş statik binary'ler için)
scratch              ──► 0 MB, 0 paket, 0 bilinen açık (CVE)
```

---

## 2. Distroless İmajlar (Google)

Distroless imajlar; paket yöneticisi (`apt`, `apk`), terminal kabuğu (`bash`, `sh`) veya işletim sisteminin standart yardımcı komutları olmadan sadece uygulamanızı ve onun runtime kütüphanelerini barındırır. Bu durum, saldırganların konteyner içine sızdığında kullanabileceği araçları tamamen ortadan kaldırır.

### Popüler Distroless İmaj Listesi

| İmaj Adı | İdeal Kullanım Alanı |
|:---|:---|
| `gcr.io/distroless/static-debian12` | Go, Rust gibi statik derlenmiş binary uygulamalar |
| `gcr.io/distroless/base-debian12` | `glibc` kütüphanesine ihtiyaç duyan C/C++ ve diğer binary'ler |
| `gcr.io/distroless/python3-debian12` | Python uygulamaları |
| `gcr.io/distroless/java21-debian12` | Java 21 (JVM) uygulamaları |
| `gcr.io/distroless/nodejs22-debian12` | Node.js v22 uygulamaları |

> [!WARNING]
> **Giriş Noktası (Entrypoint) Kısıtlaması:** Distroless imajlarda terminal kabuğu (`/bin/sh`) bulunmadığından, Dockerfile içerisinde `ENTRYPOINT ["sh", "-c", "my-command"]` formatı çalışmaz. Komutu doğrudan çalıştırmalısınız: `ENTRYPOINT ["/my-binary"]` veya `CMD ["app.js"]`.

---

## 3. Chainguard İmajları — Sıfır Zafiyet Hedefi

**Chainguard**, tamamen güvenliğe odaklanmış, günlük olarak güncellenen ve neredeyse **sıfır güvenlik açığı (Zero-CVE)** barındıran minimal imajlar sağlayan modern bir ekosistemdir.

```bash
# Chainguard imajının Trivy ile taranması
trivy image cgr.dev/chainguard/nginx:1.27.0
# Sonuç: Total: 0 (Critical: 0, High: 0, Medium: 0, Low: 0)

# Standart Alpine imajının taranması
trivy image nginx:1.27-alpine
# Sonuç: Total: 18 (Critical: 1, High: 3, Medium: 6, Low: 8)
```

---

## 4. OCI Artifacts — Her Türlü Dosyayı Registry'de Saklama

Açık Konteyner Girişimi (**OCI - Open Container Initiative**) standartları sayesinde, modern konteyner kayıt defterleri (registries) sadece konteyner imajlarını değil, altyapıda kullanılan diğer tüm statik dosyaları da saklayabilir. Bu dosyalara **OCI Artifacts** denir.

```
OCI Container Registry (Örn: Harbor, GHCR)
  ├── Konteyner İmajları (Docker Images)
  ├── Helm Paketleri (Charts)
  ├── Yazılım Malzeme Listesi (SBOM Dosyaları)
  ├── İmaj Güvenlik İmzaları (Cosign)
  ├── OPA/Kyverno Güvenlik Politikaları (YAML/Rego)
  └── WebAssembly (Wasm) Modülleri
```

### ORAS (OCI Registry As Storage) Kullanımı

**ORAS**, komut satırından herhangi bir dosyayı bir konteyner kayıt defterine OCI nesnesi olarak yüklemenizi ve indirmenizi sağlayan bir araçtır.

```bash
# 1. ORAS Kurulumu
curl -LO "https://github.com/oras-project/oras/releases/latest/download/oras_linux_amd64.tar.gz"
tar -zxf oras_linux_amd64.tar.gz -C /usr/local/bin oras

# 2. OPA/Kyverno politikalarını OCI nesnesi olarak registry'ye push etme
oras push ghcr.io/company/configs/kyverno-policies:v1.0 \
  --artifact-type application/vnd.opa.policy.v1+rego \
  policies/deny-latest.rego

# 3. İlgili politikayı geri çekme (Pull)
oras pull ghcr.io/company/configs/kyverno-policies:v1.0 -o ./downloaded-policies/

# 4. Registry'deki artifact detaylarını sorgulama (Manifest fetch)
oras manifest fetch ghcr.io/company/configs/kyverno-policies:v1.0 | jq .
```

---

## 5. Kyverno Politikalarının OCI Üzerinden Dağıtımı

Kubernetes kümenizdeki güvenlik kurallarını (policies) OCI registry üzerinden doğrudan çekip uygulayabilirsiniz:

```bash
# Kyverno kurallarını doğrudan OCI üzerinden çekip uygulama
kyverno apply oci://ghcr.io/company/policies:v1.0 --resource pod.yaml
```

---

## 6. Base İmaj Karşılaştırma Matrisi (2026 Standartları)

| Base İmaj | Ortalama Boyut | Ortalama CVE | Shell Desteği | Güvenlik Notu |
|:---|:---:|:---:|:---:|:---|
| `ubuntu:22.04` | 77 MB | ~180 | ✅ Evet | Geliştirme için kolay, production için tehlikeli |
| `debian:12-slim` | 75 MB | ~40 | ✅ Evet | Minimal sunucu imajı |
| `alpine:3.20` | 7 MB | ~5 | ✅ Evet (`ash`) | Çok popüler ancak libc yerine musl kullanır |
| `distroless/base` | 20 MB | ~2 | ❌ Hayır | Güvenli, sadece runtime |
| `distroless/static`| 2 MB | 0 | ❌ Hayır | Go/Rust için en ideali |
| `chainguard/static`| 1 MB | 0 | ❌ Hayır | Sıfır CVE garantili, ultra küçük |
| `scratch` | 0 MB | 0 | ❌ Hayır | Tamamen boş, bağımlılıksız binary'ler için |

---

## Özet

Distroless ve minimal imaj kullanımı, canlı ortamlarda (production) saldırı yüzeyini minimuma indirir. İmajların içinde shell/bash olmaması, olası sızma girişimlerinde saldırganın elini kolunu bağlar. Altyapı şablonlarınızı, Helm chart'larınızı ve güvenlik politikalarınızı ise **OCI Artifacts (ORAS)** kullanarak tek bir merkezi container registry altında yönetebilirsiniz.
