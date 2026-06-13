# External Secrets Operator — Güvenli Secret Yönetimi

GitOps kullanırken `Secret` nesnelerini asla şifresiz Git'e koymamalısınız. **External Secrets Operator (ESO)**, şifreleri HashiCorp Vault, AWS Secrets Manager, Azure Key Vault gibi güvenli kaynaklardan çekip Kubernetes Secret olarak sunar.

---

## Neden ESO?

| Yöntem | Güvenlik | Ölçeklenebilirlik | Rotasyon |
|:-------|:--------:|:-----------------:|:--------:|
| Secret'ı Git'e koymak | ❌ Tehlikeli | ✅ Kolay | ❌ Manuel |
| Sealed Secrets | ✅ İyi | ⚠️ Sınırlı | ❌ Manuel |
| **External Secrets (ESO)** | ✅ En iyi | ✅ Mükemmel | ✅ Otomatik |

---

## Kurulum (Helm)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set webhook.port=9443

# CRD'leri kontrol et
kubectl get crd | grep external-secrets
```

---

## HashiCorp Vault Entegrasyonu

### ClusterSecretStore

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.company.com"
      path: "secret"
      version: "v2"          # KV v2 engine
      caBundle: "<base64-ca>"
      auth:
        kubernetes:           # K8s Service Account ile auth (IRSA alternatifi)
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets-sa"
            namespace: "external-secrets"
```

### ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h               # Her saat Vault'tan yenile
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials            # Oluşturulacak K8s Secret adı
    creationPolicy: Owner           # ESO silinince Secret'ı da sil
    template:
      type: Opaque
      data:
        # Şablon kullanımı — birden fazla key'i birleştir
        connection-string: "host=postgres user={{ .username }} password={{ .password }}"
  data:
  - secretKey: password
    remoteRef:
      key: secret/production/database    # Vault path
      property: password
  - secretKey: username
    remoteRef:
      key: secret/production/database
      property: username
  dataFrom:
  - extract:
      key: secret/production/app-config    # Tüm key'leri çek
```

---

## AWS Secrets Manager Entegrasyonu (IRSA)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-1
      auth:
        jwt:                           # IRSA — IAM Role for Service Account
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rds-credentials
  namespace: production
spec:
  refreshInterval: 30m
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: rds-credentials
  dataFrom:
  - extract:
      key: production/rds/credentials    # AWS Secret adı
```

---

## Azure Key Vault Entegrasyonu

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      tenantId: "00000000-0000-0000-0000-000000000000"
      vaultUrl: "https://company-vault.vault.azure.net"
      authType: WorkloadIdentity      # Azure AD Workload Identity (2026 standardı)
      serviceAccountRef:
        name: external-secrets-sa
        namespace: external-secrets
```

---

## PushSecret — K8s Secret'ı Vault'a Yaz

ESO v0.9+ ile ters yön de mümkün — K8s Secret'larını harici store'a push etmek:

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: push-app-secret
  namespace: production
spec:
  refreshInterval: 10s
  secretStoreRefs:
  - name: vault-backend
    kind: ClusterSecretStore
  selector:
    secret:
      name: app-generated-key    # Bu K8s Secret'ı Vault'a push et
  data:
  - match:
      secretKey: api-key
      remoteRef:
        remoteKey: secret/production/generated-keys
        property: api-key
```

---

## SecretStore — Namespace Bazlı (ClusterSecretStore yerine)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore         # Namespace-scoped (ClusterSecretStore değil)
metadata:
  name: local-vault
  namespace: production   # Sadece production namespace kullanabilir
spec:
  provider:
    vault:
      server: "https://vault.company.com"
      path: "secret/production"
      version: "v2"
      auth:
        kubernetes:
          role: "production-reader"
```

---

## Otomatik Rotasyon Monitoring

```bash
# ExternalSecret durumunu kontrol et
kubectl get externalsecret -n production
kubectl describe externalsecret db-credentials -n production

# ESO logları
kubectl logs -n external-secrets \
  -l app.kubernetes.io/name=external-secrets \
  --tail=50 -f

# Son sync zamanı
kubectl get externalsecret db-credentials -n production \
  -o jsonpath='{.status.refreshTime}'
```

```promql
# ESO sync hataları (Prometheus ile)
externalsecret_sync_calls_error_total

# Başarılı sync sayısı
externalsecret_sync_calls_total{status="success"}
```

---

## Vault Dynamic Secrets — Per-Request Kimlik

Vault'un dynamic secrets özelliği ile her pod benzersiz, kısa ömürlü kimlik bilgileri alır:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: dynamic-db-creds
  namespace: production
spec:
  refreshInterval: 1h      # Her saat yeni kimlik bilgileri al
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: dynamic-db-creds
  data:
  - secretKey: username
    remoteRef:
      key: database/creds/production-role    # Vault dynamic secret path
      property: username
  - secretKey: password
    remoteRef:
      key: database/creds/production-role
      property: password
```

> [!CAUTION]
> Secret'ları base64 olarak bile Git'e eklemeyin. Base64 şifreleme değil, kodlamadır ve saniyeler içinde çözülür. Her zaman ESO veya Sealed Secrets kullanın.
