# Helm OCI Kayıt Defteri Entegrasyonu (Helm OCI Registry)

Helm v3.8+ sürümleriyle birlikte, Kubernetes chart paketlerini depolamak için geleneksel ve yönetilmesi zor olan HTTP/index.yaml tabanlı paket depoları yerine **OCI (Open Container Initiative)** uyumlu kayıt defterleri (registry) kullanılmaktadır. Bu sayede, aynı kayıt defteri (Örn: GitHub Packages - GHCR, Harbor, AWS ECR) hem Docker imajlarını hem de Helm chart'larını tek bir çatı altında barındırabilir.

---

## 1. OCI Chart ve Geleneksel Helm Deposu Karşılaştırması

```
Geleneksel Model (HTTP / index.yaml):
  1. helm repo add myrepo https://charts.example.com
  2. helm repo update (index.yaml dosyasını local bilgisayara indirir)
  3. helm install myapp myrepo/myapp --version 1.2.0

OCI Modeli (2026 Standardı):
  1. Depo eklemeye (repo add/update) gerek yoktur.
  2. Doğrudan oci:// URL'si üzerinden tek komutla indirilir ve kurulur:
     helm install myapp oci://ghcr.io/company/charts/myapp --version 1.2.0
```

### OCI Standartlarının Sağladığı Avantajlar

* **Tek Registry:** Uygulamanın Docker imajı ve Kubernetes Helm paketi aynı yerde saklanır, sürüm takibi kolaylaşır.
* **Kriptografik İmzalama:** **Cosign** ile Helm chart'ları kolayca imzalanıp doğrulanabilir.
* **Granüler Yetkilendirme:** Registry üzerindeki RBAC kuralları (kullanıcı yetkileri) chart'lar için de geçerli olur.
* **Değiştirilemez Etiketler (Immutable Tags):** Yayınlanan bir paket sürümü (Örn: v1.2.0) sonradan sessizce değiştirilemez.

---

## 2. Temel OCI Komutları

```bash
# 1. Kayıt Defterine (OCI Registry) Giriş Yapın
helm registry login ghcr.io \
  --username $GITHUB_ACTOR \
  --password $GITHUB_TOKEN

# 2. Chart Klasörünü Arşivleyin (Paketleme)
helm package ./my-chart
# Sonuç: my-chart-1.2.0.tgz paketi oluşur.

# 3. Paketi OCI Deposuna Gönderin (Push)
helm push my-chart-1.2.0.tgz oci://ghcr.io/company/charts

# 4. Paketi Local Cache'e İndirin (Pull)
helm pull oci://ghcr.io/company/charts/my-chart --version 1.2.0

# 5. Doğrudan OCI Üzerinden Kurulum Yapın (Install)
helm install myapp oci://ghcr.io/company/charts/my-chart \
  --version 1.2.0 \
  --namespace production \
  --create-namespace \
  -f values-production.yaml
```

---

## 3. GitHub Actions ile Otomatik OCI Chart Yayınlama CI Hattı

Aşağıdaki iş akışı, git deposundaki Helm chart'ı her yeni sürümde test eder, paketler ve GitHub Packages (GHCR) OCI deposuna push eder:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_oci_kayit_defteri_manifest_1.yaml](../Manifests/09_gitops/helm_oci_kayit_defteri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. ArgoCD ile OCI Chart Tanımlama

ArgoCD, sürüm 2.4+ ile birlikte OCI Helm depolarını yerel olarak destekler.

### ArgoCD Application YAML Yapılandırması

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_oci_kayit_defteri_manifest_2.yaml](../Manifests/09_gitops/helm_oci_kayit_defteri_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. FluxCD ile OCI Chart Tanımlama

FluxCD GitOps motoru ile OCI chart'ları dağıtmak için önce bir `HelmRepository` (depo tanımı) ardından bir `HelmRelease` nesnesi oluşturulmalıdır.

### `HelmRepository` Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_oci_kayit_defteri_manifest_3.yaml](../Manifests/09_gitops/helm_oci_kayit_defteri_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### `HelmRelease` Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_oci_kayit_defteri_manifest_4.yaml](../Manifests/09_gitops/helm_oci_kayit_defteri_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. OCI Chart Güvenliği (Cosign İmza Doğrulama)

OCI tabanlı chart'lar da Docker imajları gibi **Cosign** ile imzalanabilir ve doğrulanabilir:

```bash
# 1. OCI chart imzasını doğrulama
cosign verify \
  --key cosign.pub \
  ghcr.io/company/charts/my-chart:1.2.0

# 2. Chart ile birlikte üretilen SBOM (Yazılım Malzeme Listesi) doğrulama
cosign verify-attestation \
  --type spdx \
  --key cosign.pub \
  ghcr.io/company/charts/my-chart:1.2.0
```

---

## 7. Pratik Komutlar ve ORAS CLI Kullanımı

OCI kayıt defterlerinde arama yapmak veya sürüm geçmişini görmek için **ORAS CLI** (OCI Registry As Storage) aracı kullanılabilir:

```bash
# 1. OCI deposundaki chart parametrelerini ve default values dosyasını indirmeden görün:
helm show values oci://ghcr.io/company/charts/my-chart --version 1.2.0

# 2. OCI deposundaki tüm chart sürümlerini listeleyin (ORAS CLI yardımıyla):
oras repo tags ghcr.io/company/charts/my-chart

# 3. Local Helm OCI cache temizliği:
helm env # Local registry cache yolunu gösterir (~/.cache/helm/registry/)
rm -rf ~/.cache/helm/registry/*
```
