# Secrets Store CSI Driver

External Secrets Operator Git tabanlı push modeliyle çalışırken, **Secrets Store CSI Driver** pod'un dosya sistemi üzerinden doğrudan vault'tan secret okur. İki yaklaşım birbirini dışlamaz — farklı ihtiyaçlar için farklı araçlar.

---

## External Secrets vs Secrets Store CSI

```
External Secrets Operator:
  Vault/AWS/GCP → Kubernetes Secret (etcd'ye yazılır)
  Pod → Kubernetes Secret'tan env olarak okur
  Artı: Basit, yaygın
  Eksi: Secret etcd'de durur (şifreli olsa bile)

Secrets Store CSI Driver:
  Pod → CSI Driver → Vault/AWS/GCP → tmpfs mount (bellekte)
  Secret ASLA etcd'ye yazılmaz
  Artı: En güvenli yöntem, audit trail
  Eksi: Pod restart → yeniden fetch (kısa gecikme)
```

---

## Kurulum

```bash
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \      # Env var için K8s Secret sync et
  --set enableSecretRotation=true \    # Otomatik yenileme
  --set rotationPollInterval=2m        # 2 dakikada bir kontrol
```

---

## AWS Secrets Manager Provider

```bash
helm repo add aws-secrets-manager \
  https://aws.github.io/secrets-store-csi-driver-provider-aws

helm install aws-provider \
  aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  --namespace kube-system
```

```yaml
# SecretProviderClass — hangi secret, nereden?
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
  namespace: production
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "production/api/database-url"
        objectType: "secretsmanager"
        objectAlias: "db-url"
      - objectName: "production/api/jwt-secret"
        objectType: "secretsmanager"
        objectAlias: "jwt"
      - objectName: "/production/api/redis-host"
        objectType: "ssmparameter"    # SSM Parameter Store
        objectAlias: "redis-host"

  # Kubernetes Secret olarak da sync et (env var için)
  secretObjects:
  - data:
    - key: DATABASE_URL
      objectName: db-url
    - key: JWT_SECRET
      objectName: jwt
    secretName: api-secrets-synced
    type: Opaque
```

---

## HashiCorp Vault Provider

```bash
# Vault provider kurulumu
helm install vault-csi-provider hashicorp/vault \
  --namespace vault \
  --set "csi.enabled=true"
```

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-secrets
  namespace: production
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.company.com"
    roleName: "api-role"              # Vault Kubernetes auth role
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/production/api"
        secretKey: "db_password"
      - objectName: "api-key"
        secretPath: "secret/data/production/api"
        secretKey: "api_key"
```

---

## GCP Secret Manager Provider

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: gcp-secrets
  namespace: production
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/my-project/secrets/db-password/versions/latest"
        fileName: "db-password"
      - resourceName: "projects/my-project/secrets/api-key/versions/3"
        fileName: "api-key"
```

---

## Pod'da Kullanım

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-pod
  namespace: production
spec:
  serviceAccountName: api-service    # IRSA/Workload Identity için SA

  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: aws-secrets    # Yukarıda tanımlanan

  containers:
  - name: api
    image: ghcr.io/company/api:v2
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets"      # Secret'lar burada dosya olarak görünür
      readOnly: true

    # Yöntem 1: Dosyadan oku
    command: ["sh", "-c", "export DB_URL=$(cat /mnt/secrets/db-url) && ./server"]

    # Yöntem 2: syncSecret ile env var (SecretProviderClass'ta tanımlandıysa)
    env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: api-secrets-synced   # CSI driver oluşturdu
          key: DATABASE_URL
    - name: JWT_SECRET
      valueFrom:
        secretKeyRef:
          name: api-secrets-synced
          key: JWT_SECRET
```

---

## Otomatik Secret Rotasyonu

```yaml
# Vault'taki secret değiştiğinde pod otomatik yeniler
# (pod restart gerekmez)

# rotationPollInterval: 2m → CSI driver 2 dakikada kontrol eder
# Secret değişmişse dosyayı günceller
# Env var için: pod restart gerekli (syncSecret güncellenir)

# Uygulamada: SIGHUP ile config reload
lifecycle:
  postStart:
    exec:
      command:
      - sh
      - -c
      - |
        # secret rotasyonunu izle ve reload et
        while true; do
          sleep 120
          kill -HUP 1    # Ana process'e SIGHUP gönder
        done &
```

---

## İzleme

```bash
# CSI driver durumu
kubectl get pods -n kube-system -l app=csi-secrets-store

# SecretProviderClass bağlı pod'lar
kubectl get secretproviderclasspodstatuses -n production

# Secret son fetch zamanı
kubectl describe secretproviderclasspodstatus \
  api-pod-production-aws-secrets -n production

# Hata logları
kubectl logs -n kube-system \
  -l app=csi-secrets-store -c secrets-store
```

---

## Hangi Yöntemi Seç?

| Senaryo | Öneri |
|:--------|:------|
| Basit başlangıç | External Secrets Operator |
| Secret etcd'ye yazılmasın | **Secrets Store CSI** |
| Compliance (PCI-DSS, HIPAA) | **Secrets Store CSI** |
| Secret her yerde env var | External Secrets |
| Vault audit trail şart | **Secrets Store CSI** |
| Her ikisi | ESO + CSI birlikte kullanılabilir |
