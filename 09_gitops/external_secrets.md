# External Secrets Operator ile Güvenli Sır (Secret) Yönetimi

GitOps prensiplerine göre kümedeki tüm kaynaklar Git reposunda depolanmalıdır. Ancak, Kubernetes `Secret` nesnelerini (base64 kodlu olsalar dahi) Git reposuna ham veya şifresiz olarak eklemek çok büyük bir güvenlik açığıdır. Base64 bir şifreleme algoritması değil, sadece veri kodlama biçimidir.

**External Secrets Operator (ESO)**; sırlarınızı (şifreler, API anahtarları vb.) **HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, Google Secret Manager** gibi güvenli dış sistemlerde (Secret Managers) tutmanıza ve bunları Kubernetes kümesine otomatik olarak senkronize edip yerel `Secret` nesnelerine dönüştürmenize olanak tanır.

---

## 1. Neden ESO?

| Özelleştirme Yöntemi | Güvenlik Seviyesi | GitOps Uyumluluğu | Otomatik Yenileme (Rotation) |
|:---|:---:|:---:|:---:|
| **Ham Secret'ı Git'e koymak** | ❌ Çok Tehlikeli | ✅ Kolay | ❌ Yok (Manuel) |
| **Sealed Secrets (Bitnami)** | 🟡 İyi (Asimetrik Şifreli) | ✅ Kolay | ❌ Yok (Manuel) |
| **External Secrets (ESO)** | 🟢 En Güvenli (Merkezi) | ✅ Kusursuz | ⚡ Otomatik |

---

## 2. Kurulum Adımları (Helm)

External Secrets Operator'ı Kubernetes kümenize kurmak için:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set webhook.port=9443

# CRD'lerin başarıyla kurulduğunu doğrulayın
kubectl get crds | grep external-secrets
```

---

## 3. HashiCorp Vault Entegrasyonu

Vault üzerindeki sırları çekmek için önce bir bağlantı tanımı (**ClusterSecretStore**) ardından sır eşleştirme (**ExternalSecret**) nesnesi oluşturulur.

### A. `ClusterSecretStore` (Küme Genelinde Vault Bağlantısı)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [external_secrets_manifest_1.yaml](../Manifests/09_gitops/external_secrets_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. `ExternalSecret` (Sır Eşleştirme Tanımı)

Vault'taki `database/credentials` altındaki verileri çekip kümede `db-secret` adında yerel bir secret oluşturan nesne:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [external_secrets_manifest_2.yaml](../Manifests/09_gitops/external_secrets_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. AWS Secrets Manager Entegrasyonu (IRSA ile)

EKS (Elastic Kubernetes Service) üzerinde, AWS IAM rollerini ServiceAccount nesnelerine bağlayarak (**IRSA - IAM Roles for Service Accounts**) şifre çekme işlemi şu şekilde kurgulanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [external_secrets_manifest_3.yaml](../Manifests/09_gitops/external_secrets_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Azure Key Vault Entegrasyonu (Workload Identity)

Azure AKS kümelerinde **Azure Workload Identity** (kimlik doğrulama) ile Azure Key Vault üzerinden sırları çekmek için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [external_secrets_manifest_4.yaml](../Manifests/09_gitops/external_secrets_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. PushSecret — Yerel Sırları Harici Store'a Yazma (Push)

ESO v0.9+ ile tersine akış da desteklenmektedir. Kümedeki bir yerel Kubernetes Secret'ını dışarıdaki bir HashiCorp Vault veya AWS Secrets Manager deposuna yedeklemek/yazmak için **PushSecret** kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [external_secrets_manifest_5.yaml](../Manifests/09_gitops/external_secrets_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. SecretStore — İsim Alanı (Namespace) Bazlı İzolasyon

* **ClusterSecretStore:** Küme genelindeki tüm isim alanları tarafından ortak kullanılabilen merkezi bağlantıdır (Yönetici yetkileri için).
* **SecretStore:** Sadece tanımlandığı isim alanı (Namespace) içinde geçerlidir. Farklı ekiplerin birbirlerinin Vault bağlantı yetkilerini çalmasını veya erişmesini engellemek için ekiplere özel `SecretStore` tanımlanmalıdır.

---

## 8. Vault Dynamic Secrets (Dinamik Geçici Kimlik Bilgileri)

Vault'un en güçlü yanlarından biri statik şifreler yerine, istek anında veritabanı üzerinde 1 saatlik geçici kullanıcılar (**Dynamic Credentials**) oluşturmasıdır. ESO, bu geçici şifrelerin süresi bitmeden hemen önce otomatik olarak yeniler (rotation) ve yerel secret'ları günceller:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [external_secrets_manifest_6.yaml](../Manifests/09_gitops/external_secrets_manifest_6.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 9. Yönetim ve Senkronizasyon Sorun Giderme

```bash
# 1. ExternalSecret durumunu ve sync durumunu kontrol etme
kubectl get externalsecrets -n production

# 2. Senkronizasyon hatası detaylarını inceleme
kubectl describe externalsecret db-credentials -n production

# 3. Sırların en son hangi saniyede başarıyla senkronize edildiğini görme:
kubectl get externalsecret db-credentials -n production -o jsonpath='{.status.refreshTime}'

# 4. Operatör günlüklerini (log) canlı izleme
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50 -f
```
