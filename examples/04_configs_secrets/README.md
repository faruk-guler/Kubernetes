# ⚙️ Bölüm 4: Yapılandırma ve Sırlar (Configs & Secrets)

Bu dizin, uygulama ayarlarının ve hassas verilerin (şifreler, sertifikalar) yönetimi için örnekleri içerir.

## 📄 Dosyalar

| Dosya | Açıklama |
|:---|:---|
| configmap.yaml | Ortam değişkenleri ve dosya bazlı yapılandırmalar |
| secret.yaml | Şifreler, TLS sertifikaları ve Registry yetkileri |

> [!TIP]
> 2026 standartlarında, sırlar genellikle Kubernetes içerisinde manuel oluşturulmaz. Bunun yerine **External Secrets Operator (ESO)** kullanılarak AWS Secrets Manager, HashiCorp Vault veya Azure Key Vault gibi harici sistemlerden senkronize edilir. Detaylar için 04_gitops_ve_yapilandirma/03_external_secrets.md dökümanına bakınız.

---
*← Geri*
