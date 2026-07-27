# Secrets Store CSI Sürücüsü ile Harici Sırların (Secrets) Belleğe Bağlanması

Kubernetes'te şifreleri, API anahtarlarını ve veritabanı bağlantı bilgilerini güvenli yönetmek için External Secrets Operator (ESO) gibi çözümler sıklıkla tercih edilir. Ancak ESO, sırları harici kasalardan (Vault, AWS Secrets Manager) okuyarak etcd üzerindeki standart Kubernetes Secret nesnelerine senkronize eder. Bu durum, şifrelerin etcd üzerinde (şifreli de olsa) saklanması riskini beraberinde getirir.

**Secrets Store CSI Sürücüsü (Secrets Store CSI Driver)**, sırları Kubernetes veritabanına (etcd) yazmadan, doğrudan podun disk alanı içine geçici bir bellek dosya sistemi (**tmpfs**) olarak bağlayan (mount) ve pod durduğunda sırları bellekten tamamen silen ultra güvenli bir CSI sürücüsüdür.

---

## 1. External Secrets (ESO) vs. Secrets Store CSI

| Karşılaştırma Kriteri | External Secrets Operator (ESO) | Secrets Store CSI Driver |
|:---|:---:|:---:|
| **etcd Depolama Durumu** | 🔴 Evet (Kubernetes Secret olarak etcd'ye yazılır) | 🟢 Hayır (Sadece pod belleğinde - tmpfs tutulur) |
| **Bağlantı Türü** | Pod içinden env veya volume olarak bağlanır | Sadece Volume (dosya) olarak pod içine mount edilir |
| **Güvenlik Derecesi** | 🟡 Yüksek | 🟢 Çok Yüksek (PCI-DSS ve HIPAA uyumlu) |
| **Performans Etkisi** | Düşük (Sırlar yerel etcd'den hızlı okunur) | Pod başlangıcında harici kasadan çekildiği için hafif gecikme yaşanabilir |
| **Audit Trail (Denetim)** | Sadece senkronizasyon anında tetiklenir | Kasa (Vault/AWS) üzerinden pod bazlı erişim denetlenebilir |

---

## 2. Secrets Store CSI Driver Kurulumu (Helm)

Sürücüyü kümenize kurmak ve otomatik yenileme (rotation) özelliklerini aktif etmek için:

```bash
# 1. Helm deposunu ekleyin
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

# 2. Kurulumu otomatik rotasyon ve secret senkronizasyonu özellikleri aktif olacak şekilde yapın
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --set rotationPollInterval=2m # Her 2 dakikada bir kasadaki değişiklikleri denetle
```

---

## 3. Sağlayıcı (Provider) Kurulumları

Secrets Store CSI Driver, hangi harici kasa ile konuşacağını bilmek için ilgili sağlayıcı eklentisine (provider) ihtiyaç duyar:

### AWS Secrets Manager / Parameter Store Sağlayıcısı

```bash
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm install aws-provider aws-secrets-manager/secrets-store-csi-driver-provider-aws \
  --namespace kube-system
```

### HashiCorp Vault Sağlayıcısı

```bash
helm install vault-csi-provider hashicorp/vault \
  --namespace vault \
  --set "csi.enabled=true"
```

---

## 4. SecretProviderClass Yapılandırması (AWS Secrets Manager Örneği)

Harici kasadaki hangi şifrenin hangi dosya ismiyle poda bağlanacağını belirtmek için **SecretProviderClass** CRD nesnesi oluşturulmalıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [secrets_store_csi_surucusu_manifest_2.yaml](../Manifests/07_security/secrets_store_csi_surucusu_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Pod Manifesti ile Volume Obrasarak Bağlama ve Çevre Değişkeni Senkronizasyonu (Env Sync)

Şifreleri podun içine mount etmek ve aynı zamanda çevre değişkeni (Environment Variable) olarak kullanabilmek için pod tanımı şu şekilde kurgulanır:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [secrets_store_csi_surucusu_manifest_1.yaml](../Manifests/07_security/secrets_store_csi_surucusu_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Durum İzleme ve Sorun Giderme

```bash
# 1. SecretProviderClass bağlı aktif pod durumlarını listeleme
kubectl get secretproviderclasspodstatuses -n production

# 2. Şifrelerin kasadan son çekilme zamanını doğrulama
kubectl describe secretproviderclasspodstatus -n production

# 3. Bağlantı veya kimlik doğrulama hatalarında CSI driver loglarını okuma
kubectl logs -n kube-system -l app=csi-secrets-store -c secrets-store --tail=50
```

---

## 7. Özet

Secrets Store CSI Sürücüsü, en katı güvenlik standartlarına (PCI-DSS vb.) tabi olan finans ve kurumsal altyapılarda şifrelerin **etcd veritabanına hiç yazılmadan**, doğrudan ram-disk (`tmpfs`) olarak pod belleğinde yaşatılmasını sağlar. **OIDC/Workload Identity** entegrasyonuyla birleştiğinde, küme içi veri güvenliğini en üst düzeye (zero-trust) taşır.
