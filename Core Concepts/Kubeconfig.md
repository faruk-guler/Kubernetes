# Kubeconfig Yönetimi

Kubernetes cluster'larına `kubectl` veya API üzerinden erişmek için gereken tüm bağlantı ve kimlik doğrulama bilgileri **Kubeconfig** dosyasında tutulur. Varsayılan konum: `~/.kube/config`

---

## Dosya Yapısı

Bir Kubeconfig dosyası üç ana bölümden oluşur:

```yaml
apiVersion: v1
kind: Config

# 1. CLUSTER'LAR — Nereye bağlanılacak?
clusters:
- name: production
  cluster:
    server: https://k8s.company.com:6443
    certificate-authority-data: <BASE64_CA_CERT>
    # veya dosya yolu:
    # certificate-authority: /etc/kubernetes/pki/ca.crt

- name: staging
  cluster:
    server: https://staging.k8s.company.com:6443
    certificate-authority-data: <BASE64_CA_CERT>

# 2. KULLANICILAR — Kim bağlanıyor?
users:
- name: admin
  user:
    client-certificate-data: <BASE64_CERT>
    client-key-data: <BASE64_KEY>

- name: ci-bot
  user:
    token: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

- name: devops-oidc
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubelogin
      args: ["get-token", "--oidc-issuer-url=https://accounts.google.com"]

# 3. CONTEXT'LER — Hangi kullanıcı, hangi cluster?
contexts:
- name: prod-admin
  context:
    cluster: production
    user: admin
    namespace: production    # Varsayılan namespace

- name: staging-ci
  context:
    cluster: staging
    user: ci-bot
    namespace: default

# Aktif context
current-context: prod-admin
```

---

## Kimlik Doğrulama Yöntemleri

| Yöntem | Kullanım | Güvenlik |
|:-------|:---------|:---------|
| **Client Certificate** | kubeadm varsayılanı, admin erişimi | ✅ Yüksek |
| **Bearer Token** | ServiceAccount, CI/CD pipeline | ✅ Yüksek (kısa ömürlü) |
| **OIDC** | Kurumsal SSO (Google, Okta, AD) | ✅ En yüksek |
| **Exec Plugin** | Cloud CLI (aws eks, gcloud, az) | ✅ Yüksek |
| **Username/Password** | Eski yöntem | ❌ Önerilmez |

### OIDC ile Kurumsal Kimlik Doğrulama

```yaml
users:
- name: faruk
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubectl-oidc-login   # kubelogin plugin
      args:
      - get-token
      - --oidc-issuer-url=https://accounts.google.com
      - --oidc-client-id=my-k8s-app
      - --oidc-extra-scope=email,groups
```

### Exec Plugin (Cloud Provider CLI)

```yaml
# AWS EKS
users:
- name: eks-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
      - eks
      - get-token
      - --cluster-name
      - my-cluster
      - --region
      - eu-west-1
      env:
      - name: AWS_PROFILE
        value: production

# GKE
users:
- name: gke-user
  user:
    exec:
      command: gke-gcloud-auth-plugin
      apiVersion: client.authentication.k8s.io/v1beta1
```

---

## Context Yönetimi

```bash
# Tüm context'leri listele (aktif olan * ile işaretli)
kubectl config get-contexts
# CURRENT   NAME          CLUSTER       AUTHINFO   NAMESPACE
# *         prod-admin    production    admin      production
#           staging-ci    staging       ci-bot     default

# Aktif context
kubectl config current-context

# Context değiştir
kubectl config use-context staging-ci

# Tek komut için farklı context
kubectl get pods --context=staging-ci -n default

# Context silme
kubectl config delete-context old-cluster

# Context yeniden adlandır
kubectl config rename-context old-name new-name
```

### Namespace Değiştirme

```bash
# Aktif context'in varsayılan namespace'ini değiştir
kubectl config set-context --current --namespace=production

# Namespace geçici değiştir
kubectl get pods -n kube-system
```

---

## Çoklu Kubeconfig Birleştirme

```bash
# Birden fazla kubeconfig dosyasını birleştir (geçici)
export KUBECONFIG=~/.kube/config:~/.kube/client-a.yaml:~/.kube/client-b.yaml
kubectl config get-contexts   # Hepsini gösterir

# Kalıcı olarak tek dosyaya birleştir
KUBECONFIG=~/.kube/config:~/.kube/new-cluster.yaml \
  kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

# Belirli bir cluster'ı mevcut config'e ekle
# (kubeadm sonrası üretilen dosyadan):
KUBECONFIG=~/.kube/config:/etc/kubernetes/admin.conf \
  kubectl config view --flatten > /tmp/merged.yaml
mv /tmp/merged.yaml ~/.kube/config
```

---

## Cluster Ekle / Güncelle

```bash
# Yeni cluster ekle
kubectl config set-cluster my-cluster \
  --server=https://192.168.1.100:6443 \
  --certificate-authority=/path/to/ca.crt

# Yeni kullanıcı ekle (token ile)
kubectl config set-credentials ci-bot \
  --token=eyJhbGciOi...

# Yeni kullanıcı ekle (sertifika ile)
kubectl config set-credentials admin \
  --client-certificate=admin.crt \
  --client-key=admin.key

# Context oluştur
kubectl config set-context production \
  --cluster=my-cluster \
  --user=admin \
  --namespace=production

# Aktif et
kubectl config use-context production
```

---

## kubectx & kubens (Hızlı Geçiş)

```bash
# Kurulum
brew install kubectx   # macOS
# veya: kubectl krew install ctx ns

# Context listesi (fzf ile interaktif seçim)
kubectx
# Seçilen context'e geç

# Hızlı geçiş
kubectx production     # Tek komutla geç
kubectx -              # Önceki context'e dön

# Namespace listesi
kubens
kubens kube-system     # Namespace değiştir
kubens -               # Önceki namespace'e dön
```

---

## Güvenlik Kontrol Listesi

```bash
# ✅ Dosya izinlerini kısıtla
chmod 600 ~/.kube/config
chmod 700 ~/.kube/

# ✅ Git'te asla commit etme
echo "*.kubeconfig" >> ~/.gitignore_global
echo ".kube/" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global

# ✅ Sertifika son kullanma tarihini kontrol et
kubectl config view --raw \
  -o jsonpath='{.users[0].user.client-certificate-data}' | \
  base64 -d | openssl x509 -noout -dates

# ✅ Admin kubeconfig yerine sınırlı yetkili config kullan
# (Geliştiricilere cluster-admin verme)

# ✅ Hassas cluster için ayrı dosya (prod config ile dev aynı yerde olmasın)
ls ~/.kube/
# config           ← geliştirme ortamları
# prod.kubeconfig  ← production (ayrı, daha dikkatli)
```

---

## Kubeconfig Sorun Giderme

```bash
# Bağlantı sorununu tanıla
kubectl cluster-info
kubectl cluster-info dump 2>&1 | head -20

# Sertifika geçerli mi?
kubectl config view --raw \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | \
  base64 -d | openssl x509 -noout -text | grep -A2 "Validity"

# API Server'a direkt curl
APISERVER=$(kubectl config view --raw \
  -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(kubectl config view --raw \
  -o jsonpath='{.users[0].user.token}')
curl -k -H "Authorization: Bearer $TOKEN" "$APISERVER/api/v1/namespaces"

# Hangi kullanıcı olarak bağlanıyorum?
kubectl auth whoami
# veya:
kubectl get --raw /api/v1/namespaces \
  --v=6 2>&1 | grep "User="

# Token süresi dolmuş mu?
kubectl auth can-i get pods -n default
# error: You must be logged in to the server (Unauthorized)
# → Token yenile veya yeni kubeconfig al
```
