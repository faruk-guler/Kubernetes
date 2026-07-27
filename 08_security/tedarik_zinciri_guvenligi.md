# Yazılım Tedarik Zinciri Güvenliği (Software Supply Chain Security)

Modern bulut yerli (cloud-native) sistemlerde güvenlik sadece canlıya alınan kodun (production) kilitlenmesiyle bitmez. Yazılımcının klavyesinden çıkan ilk kod satırından, imajın derlenmesine, imza atılmasına ve Kubernetes üzerinde koşan canlı pod haline gelmesine kadar olan tüm akışın güvenilir ve değiştirilmemiş olduğunun kanıtlanması gerekir. Bu zincire **Yazılım Tedarik Zinciri (Software Supply Chain)** denir.

---

## 1. Tedarik Zinciri Tehdit Vektörleri

Yazılım geliştirme ve dağıtım süreçleri (CI/CD) saldırganlar için kritik birer hedeftir:

```
[Yazılımcı] ──► [ Git (Sürüm Yön.) ] ──► [ CI/CD Pipeline ] ──► [ İmaj Kayıt Def. ] ──► [ Kubernetes ]
                     │                         │                      │
                  (Risk:                    (Risk:                 (Risk:
               Yetkisiz Kod              Zararlı Bağımlılık      Ortadaki Adam /
                Gönderimi)                 veya Pipeline           Kod Değişimi)
                                            Sızması)
```

* **Zararlı Bağımlılıklar (npm, pip, Maven):** Açık kaynaklı kütüphanelerin ele geçirilmesi (Örn: SolarWinds, Log4j).
* **Pipeline Güvenlik Sızıntıları:** CI/CD sunucularındaki gizli anahtarların çalınması (Örn: CodeCov 2021).
* **İmaj Manipülasyonu:** Derleme bittikten sonra kayıt defterindeki (registry) imajın sessizce zararlı kod içeren başka bir imajla değiştirilmesi.

---

## 2. SLSA Framework (Software Artifacts için Tedarik Zinciri Seviyeleri)

Google tarafından geliştirilen **SLSA (Supply chain Levels for Software Artifacts)**, yazılım bütünlüğünü korumak ve güvenliği derecelendirmek için oluşturulmuş 4 seviyeli bir kılavuzdur:

| Seviye | Gereksinimler | Güvence Seviyesi |
|:---:|:---|:---|
| **SLSA 1** | Derleme süreci deklaratif ve belgelenmiştir. | Derleme geçmişi izlenebilir. |
| **SLSA 2** | Güvenli ve yönetilen bir build servisi (Örn: GitHub Actions) ve kriptografik imza kullanılır. | Kaynak kod ve imaj arasında değiştirilemez bağlantı kurulur. |
| **SLSA 3** | Derleme ortamı izole edilmiştir. Derleme kanıtı (provenance) üretilir. | Derlemenin manipüle edilmediği kanıtlanır. |
| **SLSA 4** | Kodlar için iki kişilik onay (two-person review) ve tamamen izole (hermetic) derleme ortamı. | Tamamen yeniden üretilebilir ve sızması imkansız bir derleme. |

```bash
# Bir imajın SLSA kanıtını (provenance) doğrulamak için slsa-verifier kullanımı:
slsa-verifier verify-image \
  ghcr.io/company/secure-api:v1.2.0 \
  --source-uri github.com/company/secure-api \
  --source-tag v1.2.0
```

---

## 3. Sigstore ve Cosign ile İmaj İmzalama

**Sigstore** projesi altında yer alan **Cosign**, konteyner imajlarını kriptografik olarak imzalamak ve doğrulamak için kullanılan endüstri standardı araçtır.

```bash
# 1. Cosign Kurulumu (Linux)
curl -LO https://github.com/sigstore/cosign/releases/download/v2.4.0/cosign-linux-amd64
sudo install cosign-linux-amd64 /usr/local/bin/cosign

# 2. Air-Gapped / Private Anahtar Çifti Üretme
cosign generate-key-pair
# Sonuç: cosign.key (Gizli anahtar - şifreyle korunur) ve cosign.pub (Açık anahtar)

# 3. İmajı digest (SHA256) kullanarak imzalama
IMAGE=registry.company.com/apps/api@sha256:abc123xyz...
cosign sign --key cosign.key $IMAGE

# 4. İmzayı açık anahtar ile doğrulama
cosign verify --key cosign.pub $IMAGE
```

### Keyless (Anahtarsız) İmzalama (Önerilen Model)

Modern CI/CD hatlarında statik özel anahtarlar saklamak yerine **Keyless** modeli kullanılır. Cosign, GitHub OIDC token'ını kullanarak geçici bir sertifika alır (**Fulcio CA**) ve imzayı genel erişilebilir şeffaf denetim loguna (**Rekor**) kaydeder.

```bash
# OIDC aktif bir CI ortamında anahtarsız imzalama:
cosign sign registry.company.com/apps/api:latest
```

---

## 4. GitHub Actions: Build, Scan ve Sign CI/CD Pipeline

Aşağıda, bir imajı derleyen, **Trivy** ile tarayan ve **Cosign** ile keyless modelde imzalayıp push eden örnek bir GitHub Actions iş akışı yer almaktadır:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [tedarik_zinciri_guvenligi_manifest_1.yaml](../Manifests/07_security/tedarik_zinciri_guvenligi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. SLSA Provenance Üretimi

Derleme bütünlüğünü kanıtlamak amacıyla, imaj ile birlikte derleme ortamını (Hangi Git commit'i, hangi CI sürümü) belgeleyen **SLSA Provenance** sertifikası (attestation) oluşturulmalıdır. GitHub Actions üzerinde [slsa-framework/slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator) kullanılarak bu süreç otomatik olarak yönetilir.

---

## 6. Kyverno ile Kubernetes'te İmza ve Politika Doğrulama

Kümeye imzasız veya yetkilendirilmemiş imajların girmesini engellemek amacıyla Kyverno politikaları tanımlanabilir.

### A. İmzasız İmajları Engelleme Politikası

Aşağıdaki kural, `production` isim alanına gönderilen podların imajlarının bizim `cosign.pub` açık anahtarımızla imzalanmış olmasını zorunlu kılar. İmzasız podlar kümede **başlatılmaz**:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [tedarik_zinciri_guvenligi_manifest_2.yaml](../Manifests/07_security/tedarik_zinciri_guvenligi_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Registry Kısıtlama ve Latest Tag Yasağı

Güvensiz dış kaynakların (Örn: Docker Hub) kullanılmasını engelleyen ve `latest` etiketini yasaklayan kural:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [tedarik_zinciri_guvenligi_manifest_3.yaml](../Manifests/07_security/tedarik_zinciri_guvenligi_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. Git Commit İmzalama

Güvenliğin ilk halkası kodun kendisidir. Bir saldırganın Git sunucusuna sızıp başka birinin adıyla sahte commit (kod değişimi) atmasını engellemek için **SSH** veya **GPG** anahtarlarıyla her commit imzalanmalıdır.

```bash
# 1. SSH Anahtarı ile imzalama yapılandırması (GPG'den daha basit ve moderndir)
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true

# 2. Yapılan commit imzasını doğrulama
git log --show-signature
```

Açık anahtarınızı GitHub profilinize "Signing Key" olarak eklediğinizde, yaptığınız tüm commit'lerin yanında yeşil **"Verified"** rozeti belirecektir.

---

## 8. Supply Chain Güvenliği Olgunluk Seviyeleri

| Katman | Başlangıç Seviyesi | Orta Seviye | İleri Seviye (Zero-Trust) |
|:---|:---|:---|:---|
| **Derleme (Build)** | Manuel / Basit CI | Yönetilen CI (GitHub Actions) | Hermetic Build (SLSA L3 Provenance) |
| **İmaj Taraması** | Manuel Kontrol | CI/CD Trivy Taraması | Trivy Operator (Sürekli Küme Taraması) |
| **İmzalama** | İmza Yok | Private Anahtar (Cosign Key) | Anahtarsız İmzalama (Cosign OIDC/Fulcio) |
| **Doğrulama** | Manuel | Kural Bazlı Kontrol | Kyverno ile Zorunlu İmza Kontrolü |
