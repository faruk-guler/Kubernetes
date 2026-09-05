# External Secrets Operator ile Güvenli Sır (Secret) Yönetimi

GitOps prensiplerine göre kümedeki tüm kaynaklar Git reposunda depolanmalıdır. Ancak, Kubernetes `Secret` nesnelerini (base64 kodlu olsalar dahi) Git reposuna ham veya şifresiz olarak eklemek çok büyük bir güvenlik açığıdır. Base64 bir şifreleme algoritması değil, sadece veri kodlama biçimidir.

**External Secrets Operator (ESO)**; sırlarınızı (şifreler, API anahtarları vb.) **HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, Google Secret Manager** gibi güvenli dış sistemlerde (Secret Managers) tutmanıza ve bunları Kubernetes kümesine otomatik olarak senkronize edip yerel `Secret` nesnelerine dönüştürmenize olanak tanır.

---

## 1. Neden ESO?

| Özelleştirme Yöntemi | Güvenlik Seviyesi | GitOps Uyumluluğu | Otomatik Yenileme (Rotation) |
| :--- | :---: | :---: | :---: |
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

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-cluster-backend
spec:
  provider:
    vault:
      server: "https://vault.company.internal:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets-operator-role"
```

### B. `ExternalSecret` (Sır Eşleştirme Tanımı)

Vault'taki `production/database` altındaki verileri çekip kümede `app-db-native-secret` adında yerel bir secret oluşturan nesne:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials-sync
  namespace: production
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-cluster-backend
    kind: ClusterSecretStore
  target:
    name: app-db-native-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_USER
      remoteRef:
        key: production/database
        property: username
    - secretKey: DB_PASS
      remoteRef:
        key: production/database
        property: password
```

---

## 4. Bulut Sağlayıcı Entegrasyonları (AWS Secrets Manager & Azure Key Vault)

ESO, genel bulut sağlayıcılarının gizli bilgi kasalarına entegre olurken şifresiz iş yükü kimlik doğrulamasını (OIDC / IAM) kullanır:

| Bulut Sağlayıcı | Kasa Servisi | Kimlik Doğrulama Mekanizması | Sağlayıcı Bloğu (`spec.provider`) |
| :--- | :--- | :--- | :--- |
| **AWS** | AWS Secrets Manager | IAM Roles for Service Accounts (IRSA) | `aws: { service: SecretsManager, region: eu-central-1 }` |
| **Azure** | Azure Key Vault | Azure Workload Identity | `azurekv: { authType: WorkloadIdentity, vaultUrl: "..." }` |

### Örnek Bulut `SecretStore` Yapılandırması (AWS IRSA)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: cloud-secrets-store
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-irsa-sa
```

---

## 5. PushSecret — Yerel Sırları Harici Store'a Yazma (Push)

ESO v0.9+ ile tersine akış da desteklenmektedir. Kümedeki bir yerel Kubernetes Secret'ını dışarıdaki bir HashiCorp Vault veya AWS Secrets Manager deposuna yedeklemek/yazmak için **PushSecret** kullanılır:

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: push-k8s-secret-to-vault
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRefs:
    - name: vault-cluster-backend
      kind: ClusterSecretStore
  selector:
    secret:
      name: my-local-secret
  data:
    - match:
        secretKey: api-token
        remoteRef:
          remoteKey: backup/tokens/api-token
```

---

## 6. SecretStore — İsim Alanı (Namespace) Bazlı İzolasyon

* **ClusterSecretStore:** Küme genelindeki tüm isim alanları tarafından ortak kullanılabilen merkezi bağlantıdır (Yönetici yetkileri için).
* **SecretStore:** Sadece tanımlandığı isim alanı (Namespace) içinde geçerlidir. Farklı ekiplerin birbirlerinin Vault bağlantı yetkilerini çalmasını veya erişmesini engellemek için ekiplere özel `SecretStore` tanımlanmalıdır.

---

## 7. Vault Dynamic Secrets ve `dataFrom` Kullanımı

Vault'un en güçlü özelliklerinden biri, statik şifreler yerine istek anında veritabanında geçici kullanıcılar (**Dynamic Credentials**) oluşturmasıdır. ESO, tek tek anahtar eşleştirmek yerine `dataFrom` kullanarak tüm dinamik kimlik ağacını tek seferde çeker ve TTL dolmadan yeniler:

```yaml
# Dinamik sırların ve hiyerarşik anahtarların tek seferde çekilmesi:
spec:
  refreshInterval: "45m" # TTL süresi bitmeden otomatik yenile
  secretStoreRef:
    name: vault-cluster-backend
    kind: ClusterSecretStore
  target:
    name: dynamic-db-credentials
  dataFrom:
    - extract:
        key: database/creds/my-dynamic-role
```

---

## 8. Yönetim ve Senkronizasyon Sorun Giderme

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
