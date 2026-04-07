# Tedarik Zinciri Güvenliği (Supply Chain Security) ve SBOM

2026 standartlarında, bir container imajının sadece tarama (vulnerability scan) işleminden geçmesi yeterli değildir; imajın **kriptografik olarak imzalanmış** olması ve bu imzanın cluster'a kabul edilmeden önce doğrulanması gerekir.

---

## 6.1 Cosign ve Sigstore ile İmaj İmzalama

Sigstore (özellikle `cosign` aracı), container imajlarını imzalamak ve doğrulamak için endüstri standardıdır.

```bash
# Cosign ile anahtar çifti oluşturma
cosign generate-key-pair

# Bir imajı imzalama (Private Key ile)
cosign sign --key cosign.key harbor.sirketim.com/myapp:v1.0

# İmajın imzasını doğrulama (Public Key ile)
cosign verify --key cosign.pub harbor.sirketim.com/myapp:v1.0
```

---

## 6.2 Kyverno ile Admission Kontrolü

İmzalanmış imajların doğrulanmasını "Deploy edilmeden hemen önce" zorunlu kılmak için Admission Controller (Kyverno) kullanılır. Eğer imaj doğrulanmazsa, Kubernetes o imajın çalışmasına izin vermez.

```yaml
# Kyverno ClusterPolicy örneği
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: check-image-signature
spec:
  validationFailureAction: Enforce   # Politikaya uymayan pod'ları reddet
  rules:
    - name: verify-image
      match:
        any:
        - resources:
            kinds:
              - Pod
      verifyImages:
      - imageReferences:
        - "harbor.sirketim.com/*"
        attestors:
        - count: 1
          entries:
          - keys:
              publicKeys: |-
                -----BEGIN PUBLIC KEY-----
                MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                -----END PUBLIC KEY-----
```

---

## 6.3 SBOM (Yazılım Malzeme Listesi)

Bir uygulamanın içinde tam olarak hangi kütüphanelerin, hangi versiyonlarla kullanıldığını standart bir JSON/SPDX formatında saklayan listedir. **Trivy** veya **Syft** kullanılarak SBOM üretilebilir.

```bash
# Syft ile SBOM Çıkartma
syft packages harbor.sirketim.com/myapp:v1.0 -o spdx-json > sbom.json

# SBOM'u Cosign ile İmaja İliştirme (Attestation)
cosign attest --predicate sbom.json --key cosign.key harbor.sirketim.com/myapp:v1.0
```

> [!TIP]
> **Black Belt Notu:** SLSA (Supply-chain Levels for Software Artifacts) Seviye 3 uyumluluğu elde etmek istiyorsanız, tüm build sürecinizi GitHub Actions veya Tekton üzerinde izole ortamlarda çalıştırmak ve elde edilen artefaktleri doğrudan Sigstore ile şeffaflık loguna (Rekor) yazdırmak zorundasınız.

---
*← [Küme Hardening](05_cluster_hardening.md) | [Ana Sayfa](../README.md)*
