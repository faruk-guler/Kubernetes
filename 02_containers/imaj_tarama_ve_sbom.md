# İmaj Güvenliği, Tarama ve SBOM (Image Scanning & SBOM)

2026 yılı standartlarında kurumsal bir konteyner imajını sadece kayıt defterine (registry) göndermek yetmez. İmajın **ne içerdiğini (SBOM)**, **hangi güvenlik açıklarını (CVE) barındırdığını** ve **içeriğin kurcalanmadığını (İmzalama)** kanıtlamanız gerekir.

Güvenli tedarik zinciri (supply chain security) sağlamak için kullanılan üç temel aracı ve Kubernetes entegrasyonlarını inceleyeceğiz:

* **Trivy / Grype:** Güvenlik açığı (vulnerability) taraması.
* **Syft:** Yazılım malzeme listesi (SBOM - Software Bill of Materials) envanteri üretimi.
* **Cosign:** OCI imajlarını imzalama ve doğrulama.

---

## 1. Trivy — Kapsamlı Güvenlik Tarayıcı

Trivy; konteyner imajlarını, dosya sistemlerini, git depolarını, Helm şablonlarını ve Kubernetes kümelerini tarayabilen çok yönlü bir güvenlik aracıdır.

### Temel CLI Kullanımı

```bash
# 1. Linux kurulumu
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.57.0

# 2. İmajı genel olarak tarama
trivy image registry.example.com/myapp:v1.0

# 3. Sadece CRITICAL ve HIGH seviyesindeki açıkları filtreleme
trivy image --severity CRITICAL,HIGH registry.example.com/myapp:v1.0

# 4. CI entegrasyonu için JSON veya GitHub formatında çıktı üretme
trivy image --format json --output trivy-report.json registry.example.com/myapp:v1.0
trivy image --format sarif --output trivy.sarif registry.example.com/myapp:v1.0
```

### Küme Genelinde Sürekli Tarama (Trivy Operator)

Kümede çalışan podları sürekli izlemek ve yeni çıkan açıkları anında tespit etmek için Trivy Operator kurulur:

```bash
helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/
helm install trivy-operator aquasecurity/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set trivy.ignoreUnfixed=true
```

```bash
# Cluster'daki tüm zafiyet raporlarını listeleme
kubectl get vulnerabilityreports -A

# Kritik zafiyet barındıran podları listeleme
kubectl get vulnerabilityreports -A -o jsonpath='{range .items[?(@.report.summary.criticalCount > 0)]}{.metadata.name}{"\n"}{end}'
```

---

## 2. Syft — Yazılım Malzeme Listesi (SBOM) Üretimi

**Syft**, bir konteyner imajının içindeki tüm paketlerin (kütüphaneler, dil bağımlılıkları vb.) envanterini çıkaran (Software Bill of Materials - SBOM) açık kaynaklı bir araçtır.

```bash
# 1. Kurulum
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# 2. SPDX formatında (endüstri standardı) SBOM üretme
syft registry.example.com/myapp:v1.0 -o spdx-json=myapp-sbom.spdx.json

# 3. CycloneDX formatında SBOM üretme
syft registry.example.com/myapp:v1.0 -o cyclonedx-json=myapp-sbom.cdx.json
```

---

## 3. Grype — Hızlı Zafiyet Tarayıcı (SBOM Tabanlı)

**Grype**, Syft tarafından üretilen SBOM dosyalarını girdi olarak alarak çok hızlı güvenlik açığı taraması yapabilir:

```bash
# 1. Kurulum
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# 2. SBOM dosyası üzerinden tarama
grype sbom:./myapp-sbom.spdx.json

# 3. Kritik açık varsa işlemi başarısız kıl (CI uyumlu)
grype registry.example.com/myapp:v1.0 --fail-on critical
```

---

## 4. Cosign — İmaj İmzalama ve Doğrulama

**Cosign**, OCI uyumlu konteyner imajlarını şifreleme anahtarlarıyla imzalayarak, imajın kaynağını doğrulamamızı ve imajın yolda değiştirilmediğini (man-in-the-middle) garanti altına almamızı sağlar.

```bash
# 1. Kurulum
curl -O -L https://github.com/sigstore/cosign/releases/download/v2.4.0/cosign-linux-amd64
install cosign-linux-amd64 /usr/local/bin/cosign

# 2. Anahtar çifti (Public & Private Key) oluşturma
cosign generate-key-pair
# Bu işlem 'cosign.key' (özel) ve 'cosign.pub' (açık) adında iki dosya oluşturur.

# 3. İmajı imzalama (Private key ile)
cosign sign --key cosign.key registry.example.com/myapp:v1.0

# 4. İmzayı doğrulama (Public key ile)
cosign verify --key cosign.pub registry.example.com/myapp:v1.0
```

---

## 5. Kyverno ile Kümede Sadece İmzalı İmajları Çalıştırma

Güvenlik politikası motoru **Kyverno** kullanarak, kümenize sadece sizin şirket anahtarınızla imzalanmış imajların deploy edilmesini zorunlu kılabilirsiniz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [imaj_tarama_ve_sbom_manifest_1.yaml](../Manifests/02_containers/imaj_tarama_ve_sbom_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Güvenli Tedarik Zinciri Süreç Özet Tablosu

| Araç | Temel Görevi | CI/CD Entegrasyonu | Ne Zaman Kullanılır? |
|:---|:---|:---|:---|
| **Syft** | SBOM (Envanter) üretir | İmaj derleme sonrasında | Her yeni etiketli (release) sürümde |
| **Trivy / Grype** | Güvenlik açıklarını (CVE) tarar | İmaj yüklemeden hemen önce | Her build aşamasında |
| **Cosign** | İmajı kriptografik imzalar | Registry'ye push edildikten sonra | Production dağıtımları öncesi |
| **Kyverno** | İmzayı ve SBOM varlığını doğrular | Kubernetes API girişinde (Admission) | Her yeni Deployment uygulamasında |

> [!WARNING]
> **Latest Etiketi Sorunu:** `latest` etiketli dinamik imajlar Cosign ile imzalanamaz. İmzalar imajın benzersiz hash değerine (`digest - SHA256`) bağlanır. Bu yüzden üretim ortamlarında her zaman `myapp:v1.0.0` veya `myapp@sha256:abc...` gibi sabit sürümler kullanılmalıdır.

---

## Özet

Güvenli tedarik zinciri (Supply Chain Security), uygulamanızın yazıldığı andan Kubernetes üzerinde çalıştırıldığı ana kadar geçen tüm aşamaların doğrulanmasını gerektirir. **Syft** ile envanter çıkarıp, **Trivy** ile açıkları taradıktan sonra **Cosign** ile imzaladığımız imajlar, kümede **Kyverno** denetiminden geçerek üretim ortamlarının en üst düzey güvenlik standartlarına (zero-trust) ulaşmasını sağlar.
