# Kubeconfig Yönetimi (Kubeconfig Management)

Kubernetes kümelerine `kubectl` komut satırı aracı, API veya diğer harici yönetim sistemleri üzerinden güvenli şekilde erişebilmek için gereken tüm bağlantı ve kimlik doğrulama (authentication) bilgileri **Kubeconfig** dosyasında tutulur. Varsayılan konum: `~/.kube/config`'dir.

---

## 1. Kubeconfig Dosya Yapısı

Bir Kubeconfig dosyası hiyerarşik olarak üç ana bölümden oluşur:

* **Clusters (Kümeler):** Bağlantı kurulacak Kubernetes kümelerinin sunucu adreslerini (`server`) ve güvenlik sertifikalarını (`certificate-authority-data`) içerir.
* **Users (Kullanıcılar):** Kümeye bağlanırken kullanılacak kimlik bilgilerini (sertifika, token veya harici login scriptleri) barındırır.
* **Contexts (Bağlamlar):** Bir cluster ile bir kullanıcıyı mantıksal olarak birleştiren ve varsayılan bir namespace tanımlayan eşleşme haritasıdır.

### Örnek Kubeconfig Şablonu (YAML)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kubeconfig_manifest_1.yaml](../Manifests/01_core/kubeconfig_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 2. Kimlik Doğrulama Yöntemleri

| Yöntem | Kullanım Amacı | Güvenlik Seviyesi |
| :--- | :--- | :--- |
| **Client Certificate (İstemci Sertifikası)** | `kubeadm` ile kurulumda varsayılan admin erişimi. | ✅ Yüksek (Ancak revoke edilmesi zordur) |
| **Bearer Token** | ServiceAccount ve CI/CD otomasyon boru hatları (pipeline). | ✅ Yüksek (Özellikle kısa ömürlü token'lar ile) |
| **OIDC (OpenID Connect)** | Kurumsal SSO entegrasyonları (Google, Okta, Active Directory). | ✅ En Yüksek (Merkezi yetkilendirme sağlar) |
| **Exec Plugin (Bulut CLI Entegrasyonu)** | Bulut sağlayıcıların (`aws eks`, `gcloud`, `az`) dinamik token üretimi. | ✅ Yüksek (Bulut yetkilerine bağlıdır) |
| **Username/Password (Kullanıcı/Şifre)** | Klasik temel kimlik doğrulama. | ❌ Güvensiz (Kaldırılmıştır / Önerilmez) |

---

## 3. Context (Bağlam) Yönetimi Komutları

Çoklu kümeler ve kullanıcılar arasında hızlı geçiş yapabilmek için `kubectl`'in context yönetim komutları kullanılır:

```bash
# Kayıtlı tüm context'leri listeleme (aktif olan * ile işaretlenir)
kubectl config get-contexts

# Aktif olan güncel context ismini görme
kubectl config current-context

# Başka bir context'e geçiş yapma (Küme değiştirme)
kubectl config use-context staging-context

# Tek seferlik komut için context belirtme
kubectl get pods --context=staging-context -n default

# Eski veya kullanılmayan bir context'i silme
kubectl config delete-context old-cluster-context

# Context adını değiştirme (Yeniden adlandırma)
kubectl config rename-context old-name new-name
```

### Varsayılan Namespace Değiştirme

Her seferinde komutun sonuna `-n production` yazmamak için aktif context'in varsayılan namespace değerini değiştirebilirsiniz:

```bash
kubectl config set-context --current --namespace=production
```

---

## 4. Çoklu Kubeconfig Dosyalarını Birleştirme

Farklı yerlerden indirdiğiniz kubeconfig dosyalarını tek bir ana dosyada birleştirmek için şu yöntemler izlenir:

```bash
# 1. Birden fazla kubeconfig dosyasını geçici olarak aktif etme
export KUBECONFIG=~/.kube/config:~/.kube/client-a.yaml:~/.kube/client-b.yaml

# 2. Bu dosyaları kalıcı olarak tek bir dosyada birleştirme (Flatten)
kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

# 3. Kubeadm ile yeni kurulan kümenin admin yetkisini mevcut config'e ekleme
KUBECONFIG=~/.kube/config:/etc/kubernetes/admin.conf kubectl config view --flatten > /tmp/merged.yaml
mv /tmp/merged.yaml ~/.kube/config
```

---

## 5. Manuel Olarak Cluster ve Kullanıcı Ekleme

```bash
# 1. Yeni bir cluster tanımla
kubectl config set-cluster test-cluster \
  --server=https://192.168.1.100:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt

# 2. Token kullanarak yeni bir kullanıcı tanımla
kubectl config set-credentials developer-user --token=token_degeri_buraya

# 3. Yeni bir context oluştur (cluster ile kullanıcıyı eşleştir)
kubectl config set-context test-context \
  --cluster=test-cluster \
  --user=developer-user \
  --namespace=default

# 4. Context'i aktif et
kubectl config use-context test-context
```

---

## 6. Hızlı Geçiş Araçları: `kubectx` ve `kubens`

Birden fazla küme ve namespace ile çalışırken geçişleri saniyelere indiren açık kaynaklı yardımcı araçlardır:

```bash
# Context listesini getirir ve seçmenizi sağlar (kubectx)
kubectx
kubectx production-context  # Doğrudan production-context'e geçer
kubectx -                   # Bir önceki context'e geri döner

# Namespace listesini getirir ve varsayılanı değiştirir (kubens)
kubens
kubens kube-system          # Varsayılan namespace'i kube-system yapar
kubens -                    # Bir önceki namespace'e geri döner
```

---

## 7. Kubeconfig Güvenlik Kontrol Listesi

```bash
# 1. Dosya izinlerini kısıtlayın (Sadece sahibi okuyabilsin)
chmod 600 ~/.kube/config
chmod 700 ~/.kube/

# 2. Dosyaları yanlışlıkla Git depolarına itmemek için global gitignore ekleyin
echo "*.kubeconfig" >> ~/.gitignore_global
echo ".kube/" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global

# 3. Sertifikaların son kullanma tarihlerini (validity) kontrol edin
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -dates
```

---

## Özet

Kubeconfig dosyası, Kubernetes API'sine erişimimizin anahtarıdır. Dosya izinlerinin sıkılaştırılması (`chmod 600`), geliştiricilere küme genelinde yetki vermek yerine sadece kısıtlı yetkili kubeconfig dosyalarının dağıtılması ve çoklu kümeler arası geçişler için **`kubectx / kubens`** araçlarının kullanılması en iyi pratikler arasındadır.
