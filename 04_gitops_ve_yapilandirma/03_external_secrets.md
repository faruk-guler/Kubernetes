# External Secrets Operator — Güvenli Secret Yönetimi

GitOps kullanırken `Secret` nesnelerini asla şifresiz Git'e koymamalısınız. **External Secrets Operator (ESO)**, şifreleri HashiCorp Vault, AWS Secrets Manager veya Azure Key Vault gibi güvenli kaynaklardan çekip Kubernetes Secret olarak sunar.

## 3.1 Neden ESO?

| Yöntem | Güvenlik | Ölçeklenebilirlik |
|:---|:---:|:---:|
| Secret'ı Git'e koymak | âŒ Tehlikeli | ✅ Kolay |
| Sealed Secrets | ✅ İyi | ⚠️ Sınırlı |
| **External Secrets (ESO)** | ✅ En iyi | ✅ Mükemmel |

## 3.2 ESO Kurulumu (Helm)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

## 3.3 HashiCorp Vault Entegrasyonu

### SecretStore Tanımı

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:                          # Kubernetes Service Account ile auth
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: "vault-auth-sa"
            namespace: "external-secrets"
```

### ExternalSecret Tanımı

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h                        # Her saat güncelle
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials-k8s-secret         # Oluşturulacak Secret'ın adı
    creationPolicy: Owner
  data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: secret/my-app/database
      property: password
  - secretKey: DB_USER
    remoteRef:
      key: secret/my-app/database
      property: username
```

## 3.4 AWS Secrets Manager Entegrasyonu

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
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

## 3.5 Bitwarden / 1Password Entegrasyonu

```yaml
# 1Password ile
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepassword:
      connectHost: https://1password-connect.example.com
      vaults:
        my-vault: 1
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-token
            key: token
            namespace: external-secrets
```

> [!CAUTION]
> Secret'ları Git reposuna base64 olarak bile olsa eklemeyin. Base64 bir şifreleme değil, yalnızca bir **kodlama** yöntemidir ve kolayca çözülür. Her zaman ESO veya Sealed Secrets kullanın.

