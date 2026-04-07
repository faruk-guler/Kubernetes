# Kubeconfig Yönetimi

Kubernetes cluster'larına `kubectl` veya API üzerinden erişmek için gerekli olan tüm bağlantı ve kimlik doğrulama bilgileri **Kubeconfig** dosyasında tutulur. Varsayılan olarak bu dosya `~/.kube/config` yolunda bulunur.

---

## 1. Kubeconfig Yapısı

Bir Kubeconfig dosyası temel olarak üç ana bölümden oluşur:

### 1.1 Clusters
Cluster'ın nerede olduğunu (server IP/URL) ve güvenli erişim için gerekli olan CA (Certificate Authority) verilerini içerir.
```yaml
clusters:
- cluster:
    certificate-authority-data: <BASE64_CA_CERT>
    server: https://127.0.0.1:6443
  name: prod-cluster
```

### 1.2 Users
Cluster'a bağlanacak kullanıcının kimlik bilgilerini (Client Cert, Client Key, Token veya User/Pass) içerir.
```yaml
users:
- name: cluster-admin
  user:
    client-certificate-data: <BASE64_CERT>
    client-key-data: <BASE64_KEY>
```

### 1.3 Contexts
Cluster ve User çiftini birleştirerek bir çalışma ortamı tanımlar. `current-context` alanı, o an hangi cluster üzerinde işlem yapıldığını belirler.
```yaml
contexts:
- context:
    cluster: prod-cluster
    user: cluster-admin
  name: production
current-context: production
```

---

## 2. Kimlik Doğrulama Yöntemleri

Kubernetes farklı kimlik doğrulama modellerini destekler:

| Yöntem | Açıklama |
|:---|:---|
| **Certificate** | En yaygın ve güvenli (kubeadm default) yöntemdir. |
| **Token** | ServiceAccount'lar için veya CI/CD süreçleri için idealdir. |
| **OIDC** | Kurumsal login (Google, Okta, Active Directory) entegrasyonu için. |
| **User/Pass** | Eski bir yöntemdir, 2026 standartlarında önerilmez. |

---

## 3. Çoklu Cluster Yönetimi (Multi-cluster)

Aynı kubeconfig dosyası içinde birden fazla cluster tanımlayabilirsiniz.

### Faydalı Komutlar:

```bash
# Tüm context'leri listele
kubectl config get-contexts

# Mevcut aktif context'i gör
kubectl config current-context

# Context değiştir (Üretime değil, teste geç)
kubectl config use-context test-cluster

# Context silme
kubectl config delete-context old-cluster
```

> [!TIP]
> Context yönetimi için [kubectx ve kubens](08_faydali_araclar.md) araçlarını kullanmak operasyonel hızı 10 kat artırır.

---

## 4. Gelişmiş Kullanım

### Farklı Kubeconfig Dosyaları Belirtmek
```bash
# Parametre ile
kubectl get pods --kubeconfig=./another-config.yaml

# Environment Variable ile (Geçici)
export KUBECONFIG=~/.kube/config:~/projects/client-a.yaml
```

### Güvenlik Notu
Kubeconfig dosyaları, cluster'ınıza erişim sağlayan **admin yetkileri** içerebilir. Bu dosyaları asla public repolara yüklemeyin ve dosya izinlerini kısıtlayın (`chmod 600 ~/.kube/config`).

---
*← [Kubectl Cheatsheet](03_kubectl_cheatsheet.md) | [Mimarisi](02_mimari_ve_bilesenler.md)*
