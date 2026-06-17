# Service Account & Workload Identity

Kubernetes üzerinde koşan uygulamalarımızın sadece kendi iç dünyalarında çalışması yetmez. Birçok uygulamanın Kubernetes API Server ile konuşması (örneğin pod listesini okumak veya bir ConfigMap'i izlemek) veya harici bulut kaynaklarına (AWS S3, Google Cloud Storage, Azure Key Vault vb.) erişmesi gerekir.
Uygulama veya Service Account bazında bu erişimlerin yönetilmesini sağlar.

---

## Service Account Nedir?

Kubernetes dünyasında iki tür kimlik (identity) vardır:

* **User Account (Kullanıcı Hesabı):** Bizler gibi gerçek insanları temsil eder. `kubectl` kullanan geliştiriciler ve sistem yöneticileri bu kimlikle cluster'a erişir. Yönetimi genellikle cluster dışındaki sistemlerle (OIDC, Active Directory vb.) yapılır.
* **Service Account (Servis Hesabı):** Pod'ların içinde çalışan uygulamaları ve süreçleri temsil eder. Kubernetes veritabanında (etcd) bir obje olarak saklanır ve doğrudan cluster tarafından yönetilir.

Her pod çalışırken mutlaka bir Service Account kullanır. Eğer pod tanımında açıkça bir Service Account belirtmezseniz, Kubernetes o namespace'teki yerleşik `default` Service Account kimliğini poda otomatik olarak atar.

---

## Güvenlik Riski: Otomatik Token Mount Etme

Varsayılan ayarlarla oluşturulan her podun içine, Kubernetes API Server ile konuşabilmesi için otomatik olarak bir Service Account Token'ı (bir JWT anahtarı) dosya olarak mount edilir. Bu dosya container içinde `/var/run/secrets/kubernetes.io/serviceaccount/token` adresinde durur.

> [!WARNING]
> **Güvenlik Riski:** Eğer uygulamanızın Kubernetes API ile konuşmasına gerek yoksa, bu token'ın pod içine mount edilmesi büyük bir güvenlik açığıdır. Uygulamanızda oluşabilecek bir güvenlik zafiyetinde (örneğin Remote Code Execution), saldırgan pod içine sızıp bu token'ı ele geçirebilir ve API Server üzerinde yetkisiz işlemler gerçekleştirebilir.

Bu riski önlemek için API erişimine ihtiyacı olmayan pod'larda veya Service Account'un kendisinde token mount özelliğini kapatmalıyız:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-service
  namespace: production
# Otomatik token mount etmeyi kapat
automountServiceAccountToken: false
```

Eğer sadece belirli pod'larda bu özelliği kapatmak istiyorsak pod tanımının içine yazabiliriz:

```yaml
spec:
  serviceAccountName: backend-service
  automountServiceAccountToken: false   # Poda özel kapatma
```

---

## Projected Token (Kısa Ömürlü ve Güvenli Token)

Eski Kubernetes sürümlerinde oluşturulan Service Account token'ları süresizdi (sonsuza kadar geçerliydi) ve etcd üzerinde statik Secret objeleri olarak saklanıyordu. Bu token'lardan biri çalındığında iptal edilmesi son derece zordu.

Modern Kubernetes mimarisinde (özellikle 2026 standartlarında) artık **Projected Service Account Token** yapısı kullanılır. Bu yöntemde token'lar etcd'ye yazılmaz; doğrudan kubelet tarafından üretilir, kısa ömürlüdür (örneğin 1 saat) ve süresi doldukça kubelet tarafından container içinde otomatik olarak yenilenir.

```yaml
spec:
  volumes:
  - name: secure-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600        # 1 saat geçerlilik süresi
          audience: "https://api.company.com"
  containers:
  - name: app
    volumeMounts:
    - name: secure-token
      mountPath: /var/run/secrets/api
```

---

## RBAC ile Yetkilendirme

Oluşturduğumuz bir Service Account'un API Server üzerinde ne yapabileceğini belirlemek için **RBAC (Role-Based Access Control)** kullanırız.
Aşağıda, oluşturduğumuz `api-service` isimli Service Account'a sadece kendi namespace'indeki `ConfigMap` ve `Secret` nesnelerini okuma yetkisi veren örnek bir Role ve RoleBinding tanımı yer almaktadır:

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

## Bulut Kaynaklarına Güvenli Erişim: Workload Identity

Geleneksel mimaride pod içindeki bir uygulamanın bulut servislerine (örneğin AWS S3 veya Google Cloud Storage) erişebilmesi için donanım anahtarları (AWS Access Key/Secret Key veya GCP Service Account JSON dosyası) oluşturulup Kubernetes Secret'ları içine yazılırdı.

* **Riskler:** Bu anahtarların çalınma riski yüksektir, süreleri dolmaz ve düzenli aralıklarla değiştirilmeleri (key rotation) operasyonel olarak çok zordur.
* **Çözüm (Workload Identity):** Kubernetes Service Account ile bulut sağlayıcısının IAM (Identity and Access Management) rolleri arasında güven ilişkisi (OIDC federasyonu) kurulmasıdır. Pod çalıştığında Kubernetes'ten aldığı kısa ömürlü JWT token'ını bulut sağlayıcısına gönderir. Bulut sağlayıcı bu token'ı doğrular ve pod'a geçici, kısa ömürlü bir IAM rolü atar. Cluster içinde hiçbir şifre veya statik anahtar saklanmaz.

### 1. AWS — IRSA (IAM Roles for Service Accounts)

AWS EKS üzerinde IRSA yapılandırma adımları:

```bash
# EKS Cluster'ı için OIDC Identity Provider aktifleştirme
eksctl utils associate-iam-oidc-provider --cluster my-cluster --approve

# AWS IAM üzerinde Kubernetes Service Account'una güvenen bir rol oluşturma
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC=$(aws eks describe-cluster --name my-cluster \
  --query "cluster.identity.oidc.issuer" --output text | sed s@https://@@)

aws iam create-role --role-name api-s3-role \
  --assume-role-policy-document "{
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"Federated\": \"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC}\"},
      \"Action\": \"sts:AssumeRoleWithWebIdentity\",
      \"Condition\": {\"StringEquals\": {
        \"${OIDC}:sub\": \"system:serviceaccount:production:api-service\"
      }}
    }]}"

# Rolü gerekli izinlerle (Örn: S3 Read Only) yetkilendirme
aws iam attach-role-policy --role-name api-s3-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

Ardından, oluşturduğumuz Kubernetes Service Account'u bu IAM rolü ile ilişkilendiririz (AWS SDK'ları bu annotation'ı görünce token alışverişini arka planda otomatik yapar):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/api-s3-role
```

### 2. GKE — Workload Identity

Google Cloud GKE üzerinde Workload Identity yapılandırması:

```bash
# Google Cloud IAM üzerinde bir Service Account (GSA) oluşturun
gcloud iam service-accounts create api-gsa --project=my-project

# GSA'yı bulut kaynakları için yetkilendirin (Örn: Storage Viewer)
gcloud projects add-iam-policy-binding my-project \
  --member "serviceAccount:api-gsa@my-project.iam.gserviceaccount.com" \
  --role "roles/storage.objectViewer"

# Kubernetes Service Account (KSA) ile GSA arasında eşleşme kurun
gcloud iam service-accounts add-iam-policy-binding \
  api-gsa@my-project.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:my-project.svc.id.goog[production/api-service]"
```

Kubernetes Service Account manifestosuna eklenen annotation:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: production
  annotations:
    iam.gke.io/gcp-service-account: api-gsa@my-project.iam.gserviceaccount.com
```

### 3. Azure — Workload Identity

AKS üzerinde Azure Workload Identity kullanımı:

```bash
# AKS üzerinde OIDC ve Workload Identity özelliklerini açın
az aks update -n my-cluster -g my-rg \
  --enable-oidc-issuer --enable-workload-identity

# Azure Managed Identity oluşturun
az identity create --name api-identity --resource-group my-rg

# Eşleşme credential tanımını yapın
OIDC=$(az aks show -n my-cluster -g my-rg --query "oidcIssuerProfile.issuerUrl" -o tsv)

az identity federated-credential create \
  --name api-fedcred --identity-name api-identity \
  --resource-group my-rg --issuer $OIDC \
  --subject "system:serviceaccount:production:api-service"
```

---

## Güvenlik En İyi Pratikleri (Best Practices)

* **İzolasyon:** Her mikro servis veya uygulama için bağımsız bir Service Account oluşturun. Ortak veya varsayılan `default` hesabı asla kullanmayın.
* **En Az Yetki İlkesi (PoLP):** Oluşturduğunuz rolleri olabildiğince dar tanımlayın. Namespace seviyesindeki işler için `ClusterRole` yerine `Role` tercih edin.
* **Token Temizliği:** Kubernetes API Server ile doğrudan iletişime geçmeyen (Örn: standart bir web frontend pod'u) tüm pod'larda `automountServiceAccountToken: false` yaparak token erişimini kapatın.

---

## Yetki Doğrulama ve Test Komutları

Bir Service Account'un yetkilerini test etmek için cluster yöneticisi olarak aşağıdaki komutları kullanabilirsiniz:

```bash
# api-service hesabının production namespace'inde pod listeleme yetkisi var mı?
kubectl auth can-i list pods \
  --as=system:serviceaccount:production:api-service -n production

# Bu hesabın o namespace'teki tüm yetki listesini görme
kubectl auth can-i --list \
  --as=system:serviceaccount:production:api-service -n production
```
