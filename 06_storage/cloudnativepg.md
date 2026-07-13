# CloudNativePG ile PostgreSQL Veritabanı Yönetimi

Geleneksel teknoloji yaklaşımlarında "durumlu veritabanı iş yükleri kesinlikle Kubernetes üzerinde çalıştırılmamalıdır" denirdi. Ancak 2026 yılı standartlarında **Operator Pattern (Operatör Tasarımı)** mimarisi sayesinde, Kubernetes üzerinde PostgreSQL barındırmak ve yönetmek, bulut sağlayıcılarının yönetilen servislerinden (AWS RDS vb.) daha ekonomik, daha yüksek performanslı ve tam kontrollü bir model haline gelmiştir.

**CloudNativePG (CNPG)**, PostgreSQL küme yönetimini, yedeklemelerini ve felaket kurtarma (disaster recovery) senaryolarını tamamen otomatize eden CNCF Incubating statüsünde bir operatördür.

---

## 1. CloudNativePG Özellikleri

Bir veritabanı yöneticisinin (DBA) tüm operasyonel bilgi birikimini koda ve Kubernetes API'sine dökerek şu işlemleri otomatik gerçekleştirir:

* **Otomatik Yüksek Kullanılabilirlik (HA):** Primary pod çöktüğü anda replikasyon gecikmesi en az olan replica podu otomatik olarak yeni primary seçilir (Failover) ve küme trafiği kesintisiz yönlendirilir.
* **Sıfır Veri Kayıplı Yedekleme:** Sürekli WAL (Write-Ahead Log) arşivleme ve periyodik base yedekleri doğrudan nesne depolama (S3, MinIO vb.) alanlarına yazılır.
* **Kesintisiz Güncelleme (Rolling Upgrade):** PostgreSQL major sürüm güncellemeleri podlar sırayla kapatılarak ve otomatik geçişler yapılarak sıfır kesintiyle uygulanır.
* **PgBouncer Entegrasyonu:** Dahili ve yönetilen connection pooling desteği sunar.

---

## 2. CloudNativePG Kurulumu

CNPG operatörünü kümenize kurmak için:

```bash
# 1. En kararlı sürüm manifestosunu uygulayın (v1.25.0)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.25.0.yaml

# 2. Kurulum durumunu doğrulayın
kubectl get deployment -n cnpg-system
```

---

## 3. PostgreSQL Kümesi Oluşturma

CNPG ile 3 düğümlü (1 Primary, 2 Read-Replica) yüksek erişilebilir bir PostgreSQL veritabanı kurmak için aşağıdaki manifest yeterlidir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cloudnativepg_manifest_1.yaml](../Manifests/06_storage/cloudnativepg_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Yedekleme ve Kurtarma (Backup & Restore)

### Manuel Yedek Başlatma

```bash
# Veritabanının anlık yedeğini alın
kubectl cnpg backup postgres-prod -n production
```

### Belirli Bir Zamana Geri Dönme (PITR - Point-In-Time-Recovery)

Bir felaket anında (Örn: Verilerin yanlışlıkla silinmesi), veritabanını belirli bir tarihteki tam dakikasına geri döndürmek için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cloudnativepg_manifest_2.yaml](../Manifests/06_storage/cloudnativepg_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Servisler ve Bağlantı Yönetimi (Connection Management)

CNPG, veritabanı oluştuktan sonra trafiği doğru podlara yönlendirmek için 3 adet servis üretir:

* `postgres-prod-rw` (Read-Write): Yalnızca Primary podunu gösterir. Tüm yazma işlemleri bu adrese yapılır.
* `postgres-prod-ro` (Read-Only): Sadece Replica podlarını gösterir. Okuma işlemlerini replicalar arasında yük dengeler.
* `postgres-prod-r` (Read): Tüm podları (Primary dahil) okuma amaçlı gösterir.
