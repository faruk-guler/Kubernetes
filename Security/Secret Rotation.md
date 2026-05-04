# Secret Rotation — Otomatik Sır Yenileme

Production ortamlarında secret'ların periyodik olarak yenilenmesi güvenlik için zorunludur. Sızdırılmış bir token'ın hasarı, rotasyon sıklığıyla doğrudan orantılıdır.

---

## Neden Rotasyon?

| Risk | Rotasyonsuz | Rotasyonlu |
|:-----|:-----------|:-----------|
| Sızdırılan token | Sonsuza kadar geçerli | Max rotasyon süresi kadar |
| Ayrılan çalışan | Erişim manuel iptal gerekir | Otomatik sona erer |
| Compliance (SOC2, PCI) | Başarısız | Geçer |
| Blast radius | Büyük | Sınırlı |

---

## External Secrets Operator — Otomatik Rotasyon

ESO, `refreshInterval` ile secret'ları Vault/AWS'den periyodik çeker:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h      # Her saat Vault'tan güncelle
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: secret/my-app/database
      property: password
```

> [!TIP]
> `refreshInterval: 1h` ile ESO her saat Vault'u kontrol eder. Vault'ta rotasyon yapıldığında K8s Secret otomatik güncellenir. Uygulamanın yeni değeri alması için **Reloader** kullanın.

---

## HashiCorp Vault — Dynamic Secrets

Vault'un en güçlü özelliği: her uygulama isteği için **benzersiz, kısa ömürlü kimlik bilgisi** üretmek.

```bash
# Vault'ta PostgreSQL dynamic secret engine'i etkinleştir
vault secrets enable database

# Veritabanı bağlantısı tanımla
vault write database/config/my-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres.production:5432/mydb" \
  username="vault-admin" \
  password="vault-admin-pass"

# Role tanımla — her token için yeni kullanıcı oluştur
vault write database/roles/app-role \
  db_name=my-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' \
    VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

```bash
# Test: yeni kimlik bilgisi al
vault read database/creds/app-role
# username: v-app-role-xK9mP2
# password: A1B2-C3D4-E5F6
# lease_duration: 1h
```

```yaml
# ESO ile Vault dynamic secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-dynamic-creds
  namespace: production
spec:
  refreshInterval: 45m     # TTL=1h, 45dk'da bir yenile
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: postgres-creds
  data:
  - secretKey: username
    remoteRef:
      key: database/creds/app-role
      property: username
  - secretKey: password
    remoteRef:
      key: database/creds/app-role
      property: password
```

---

## AWS Secrets Manager — Otomatik Rotasyon

```bash
# Rotasyonu etkinleştir (Lambda fonksiyonu ile)
aws secretsmanager rotate-secret \
  --secret-id prod/myapp/db \
  --rotation-rules AutomaticallyAfterDays=30

# Rotasyon durumunu kontrol et
aws secretsmanager describe-secret \
  --secret-id prod/myapp/db \
  --query 'RotationEnabled'
```

```yaml
# ESO ile AWS Secrets Manager (otomatik rotasyon uyumlu)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: aws-db-creds
  namespace: production
spec:
  refreshInterval: 30m
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: db-creds
  data:
  - secretKey: password
    remoteRef:
      key: prod/myapp/db
      property: password
      version: AWSCURRENT    # Her zaman güncel sürümü al
```

---

## Reloader — Secret Değişince Otomatik Restart

ESO secret'ı güncellediğinde, uygulama pod'larının yeni değeri alması için restart gerekir:

```yaml
# Deployment'a annotation ekle
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
    secret.reloader.stakater.com/reload: "db-creds,postgres-creds"
```

```bash
# Reloader kurulumu (zaten Tools bölümünde anlatılmıştır)
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader \
  --namespace reloader \
  --create-namespace
```

---

## Kubernetes ServiceAccount Token Rotasyonu

Kubernetes 1.22+ ile token'lar otomatik olarak sona erer ve yenilenir:

```yaml
# Kısa ömürlü, audience'a özel token
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: production
---
# Pod'a projected token mount et
spec:
  serviceAccountName: my-app-sa
  volumes:
  - name: token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600     # 1 saatte sona erer
          audience: my-app            # Sadece bu audience için geçerli
```

---

## Rotasyon Sıklığı Rehberi

| Secret Türü | Önerilen Sıklık | Yöntem |
|:------------|:----------------|:-------|
| Veritabanı şifresi | 30 günde bir | Vault Dynamic / AWS Rotation |
| API key (3rd party) | 90 günde bir | ESO + refreshInterval |
| TLS sertifikası | 60-90 günde bir | cert-manager (otomatik) |
| ServiceAccount token | 1-24 saat | K8s Projected Token |
| Docker registry | 12 saatte bir | ECR/GCR token otomatik |

> [!CAUTION]
> Rotasyon yaparken **sıfır kesinti** hedeflenmeli. Strateji: yeni secret oluştur → uygulamayı rolling restart ile güncelle → eski secret'ı sil. Vault dynamic secrets bu akışı otomatikleştirir.
