# Otomatik Sır Yenileme (Secret Rotation)

Üretim (production) ortamlarında veritabanı şifreleri, API anahtarları ve sertifikalar gibi kritik sırların (secrets) belirli periyotlarla değiştirilmesi güvenlik uyumluluk standartlarının (SOC2, PCI-DSS vb.) en temel gereksinimlerinden biridir. Sızdırılan veya çalınan bir şifrenin yaratacağı zarar, o şifrenin geçerlilik süresi (rotasyon sıklığı) ile doğrudan orantılıdır.

---

## 1. Neden Rotasyon Yapmalıyız?

| Risk Türü | Rotasyonsuz Altyapı | Rotasyonlu Altyapı (Zero-Trust) |
|:---|:---|:---|
| **Sızdırılan Şifreler** | İptal edilene kadar sonsuza kadar geçerlidir. | Maksimum rotasyon süresi kadar geçerlidir. |
| **Ayrılan Çalışanlar** | Tüm şifrelerin manuel değiştirilmesi gerekir. | Otomatik yenilenerek eski erişimler geçersizleşir. |
| **Güvenlik Uyumluluğu** | Denetimlerden (PCI/SOC2) kalınır. | Kolayca geçilir. |
| **Saldırı Etki Alanı** | Devasa ve yıkıcıdır. | Sınırlı ve kontrol altındadır. |

---

## 2. External Secrets Operator (ESO) ile Otomatik Yenileme

ESO, harici kasalardan (Vault, AWS Secrets Manager vb.) verileri çekerken `refreshInterval` parametresini kullanarak Kubernetes Secret nesnelerini belirli aralıklarla otomatik olarak senkronize eder (günceller).

### Örnek `ExternalSecret` Yapılandırması

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [secret_rotasyonu_manifest_1.yaml](../Manifests/07_security/secret_rotasyonu_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

> [!TIP]
> `refreshInterval: 1h` ayarlandığında, harici kasada yapılan şifre değişiklikleri en geç 1 saat içinde Kubernetes tarafındaki Secret nesnesine yansıtılır.

---

## 3. HashiCorp Vault ile Dinamik Sırlar (Dynamic Secrets)

Statik şifreleri döndürmenin ötesinde, en güvenli yaklaşım **Dinamik Sırlar (Dynamic Secrets)** kullanmaktır. Dinamik sırlar modelinde, pod veritabanına bağlanmak istediğinde Vault, veritabanı üzerinde o pod'a özel, benzersiz ve geçici (örneğin 1 saat ömürlü) bir veritabanı kullanıcısı oluşturur. Süre dolduğunda bu kullanıcı otomatik olarak silinir.

### Vault PostgreSQL Dinamik Sır Yapılandırması

```bash
# 1. Database motorunu aktif edin
vault secrets enable database

# 2. Veritabanı bağlantı bilgilerini tanımlayın
vault write database/config/my-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres.production:5432/mydb" \
  username="vault-admin" \
  password="vault-admin-pass"

# 3. Rolü ve SQL komutlarını oluşturun (Geçici kullanıcı yaratma)
vault write database/roles/app-role \
  db_name=my-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' \
    VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

```bash
# Pod veya yazılım bu kimlik bilgisini talep ettiğinde:
vault read database/creds/app-role

# Sonuç:
# username: v-app-role-xK9mP2 (Otomatik üretilen kullanıcı)
# password: A1B2-C3D4-E5F6 (Otomatik üretilen şifre)
# lease_duration: 1h (1 saat sonra silinecek)
```

---

## 4. AWS Secrets Manager ile Otomatik Rotasyon

AWS tarafında şifrelerin periyodik olarak değiştirilmesi, arka planda çalışan bir **AWS Lambda** fonksiyonu ile otomatikleştirilir.

```bash
# Bir secret için Lambda destekli 30 günlük rotasyonu aktifleştirme:
aws secretsmanager rotate-secret \
  --secret-id prod/myapp/db \
  --rotation-rules AutomaticallyAfterDays=30

# Rotasyon durumunu sorgulama:
aws secretsmanager describe-secret \
  --secret-id prod/myapp/db \
  --query 'RotationEnabled'
```

---

## 5. Reloader ile Sır Değişiminde Sıfır Kesintili Rolling Update

Kubernetes'te bir Secret güncellendiğinde, bu secret'ı çevre değişkeni (env) olarak kullanan pod'lar bu güncellemeden haberdar olmaz. Pod'ların yeni şifreyi alabilmesi için yeniden başlatılmaları gerekir.

**Reloader**, Secret veya ConfigMap üzerindeki değişiklikleri izleyen ve bu kaynaklara bağlı olan Deployment'ları sıfır kesintiyle otomatik olarak yeniden başlatan (rolling update) harici bir denetleyicidir.

### Reloader Kurulumu

```bash
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update
helm install reloader stakater/reloader --namespace reloader --create-namespace
```

### Deployment Üzerinde Kullanımı

Deployment tanımındaki annotation (açıklama) alanına Reloader etiketini eklemeniz yeterlidir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [secret_rotasyonu_manifest_2.yaml](../Manifests/07_security/secret_rotasyonu_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Kubernetes ServiceAccount Token Rotasyonu

Kubernetes 1.22+ ile birlikte varsayılan olarak **Projected ServiceAccount Token (Bound ServiceAccount Tokens)** modeli gelmiştir.

Kubelet, pod içine mount edilen ServiceAccount token'larını (`/var/run/secrets/kubernetes.io/serviceaccount/token`) otomatik olarak yönetir:

* Token'ların varsayılan ömrü 1 saattir.
* Kubelet, bu sürenin dolmasına 10-15 dakika kala arka planda API sunucusu ile konuşarak token'ı yeniler ve pod içindeki dosyaya güncel halini yazar.
* Eğer pod hacklenirse ve token çalınırsa, çalınan bu token en fazla 1 saat boyunca kullanılabilir.

---

## 7. Rotasyon Sıklığı ve Yöntem Kılavuzu

| Sır Türü (Secret Type) | Önerilen Rotasyon Sıklığı | En Uygun Yöntem |
|:---|:---:|:---|
| **Veritabanı Şifreleri** | 30 Günde Bir | Vault Dynamic Secrets / AWS Rotation Lambda |
| **Üçüncü Parti API Anahtarları** | 90 Günde Bir | ESO (`refreshInterval`) + Reloader |
| **TLS / SSL Sertifikaları** | 60-90 Günde Bir | `cert-manager` (Let's Encrypt ile tam otomatik) |
| **ServiceAccount Token'ları** | 1 - 24 Saat | Kubernetes Bound ServiceAccount Tokens (Yerleşik) |
| **Konteyner Kayıt Defterleri (Registry)** | 12 Saat | ECR / GCR credential helper (Kubelet otomatik yeniler) |

> [!CAUTION]
> **Sıfır Kesinti (Zero-Downtime) Kuralı:** Rotasyon işlemi yapılırken eski şifre ile yeni şifre veritabanında aynı anda belirli bir süre (örneğin 1-2 gün) geçerli olmalıdır. Aksi takdirde, pod'ların rolling update ile güncellenme sürecinde eski şifreyi kullanan pod'lar veritabanına erişemez ve sisteminiz kesintiye uğrar.
