# Service Account & Workload Identity

Pod'ların Kubernetes API'sine ve bulut kaynaklarına kimlik doğrulaması — 2026'da kritik güvenlik konusu.

---

## Service Account Nedir?

```
İnsan → kubectl → API Server (kullanıcı kimliği)
Pod   → API Server (Service Account kimliği)

Her pod bir SA ile çalışır. Belirtilmezse: "default" SA.
```

---

## Service Account Oluşturma

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
automountServiceAccountToken: false   # Güvenlik için varsayılanı kapat
```

```yaml
spec:
  serviceAccountName: api-service
  automountServiceAccountToken: true    # Sadece gerekliyse aç
```

---

## Projected Token (Kısa Ömürlü)

```yaml
spec:
  volumes:
  - name: api-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600        # 1 saatlik token
          audience: "https://api.company.com"
  containers:
  - name: app
    volumeMounts:
    - name: api-token
      mountPath: /var/run/secrets/api
```

---

## RBAC ile Yetkilendirme

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: config-reader
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-config-reader
  namespace: production
subjects:
- kind: ServiceAccount
  name: api-service
  namespace: production
roleRef:
  kind: Role
  name: config-reader
  apiGroup: rbac.authorization.k8s.io
```

---

## AWS — IRSA (IAM Roles for Service Accounts)

```bash
# OIDC provider'ı IAM'e kaydet
eksctl utils associate-iam-oidc-provider \
  --cluster my-cluster --approve

# Federated trust ile IAM Role oluştur
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC=$(aws eks describe-cluster --name my-cluster \
  --query "cluster.identity.oidc.issuer" --output text | sed s@https://@@)

aws iam create-role --role-name api-role \
  --assume-role-policy-document "{
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"Federated\": \"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC}\"},
      \"Action\": \"sts:AssumeRoleWithWebIdentity\",
      \"Condition\": {\"StringEquals\": {
        \"${OIDC}:sub\": \"system:serviceaccount:production:api-service\"
      }}
    }]}"

aws iam attach-role-policy --role-name api-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

```yaml
# SA annotation — SDK otomatik token kullanır
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/api-role
```

---

## GKE — Workload Identity

```bash
# Google SA oluştur + yetki ver
gcloud iam service-accounts create api-gsa --project=my-project
gcloud projects add-iam-policy-binding my-project \
  --member "serviceAccount:api-gsa@my-project.iam.gserviceaccount.com" \
  --role "roles/storage.objectViewer"

# K8s SA ↔ Google SA bağlantısı
gcloud iam service-accounts add-iam-policy-binding \
  api-gsa@my-project.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:my-project.svc.id.goog[production/api-service]"
```

```yaml
metadata:
  annotations:
    iam.gke.io/gcp-service-account: api-gsa@my-project.iam.gserviceaccount.com
```

---

## Azure — Workload Identity

```bash
az aks update -n my-cluster -g my-rg \
  --enable-oidc-issuer --enable-workload-identity

az identity create --name api-identity --resource-group my-rg

OIDC=$(az aks show -n my-cluster -g my-rg \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

az identity federated-credential create \
  --name api-fedcred --identity-name api-identity \
  --resource-group my-rg --issuer $OIDC \
  --subject "system:serviceaccount:production:api-service"
```

---

## Güvenlik Best Practices

```yaml
# ✅ Her uygulama için ayrı SA (default kullanma)
# ✅ automountServiceAccountToken: false (gereksiz mount engelle)
# ✅ expirationSeconds: 3600 (kısa ömürlü token)
# ✅ En az yetki — sadece gerekli verb ve resource
# ❌ cluster-admin SA kullanmak
# ❌ Statik token hard-code etmek
```

```bash
# SA yetkilerini doğrula
kubectl auth can-i list pods \
  --as=system:serviceaccount:production:api-service -n production

kubectl auth can-i --list \
  --as=system:serviceaccount:production:api-service -n production
```
