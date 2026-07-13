# Velero ile Küme Yedekleme ve Taşıma (Velero Backup & Restore)

**Velero** (eski adıyla Heptio Ark), Kubernetes kümesindeki kaynakları (YAML manifestolarını) ve kalıcı disk verilerini (Persistent Volume verileri) güvenli bir şekilde yedekleyen, geri yükleyen ve kümeler arası taşıyan (migration) kurumsal seviyede açık kaynaklı bir felaket kurtarma (DR) aracıdır.

---

## 1. Velero Mimarisi ve Nasıl Çalışır?

Velero, iki temel katman üzerinden yedekleme gerçekleştirir:

1. **Kubernetes Nesne Yedeklemesi:** Kümedeki tüm YAML kaynakları (Deployments, Services, ConfigMaps, RBAC kuralları vb.) Kubernetes API üzerinden okunarak bir sıkıştırılmış tarball (.tar.gz) dosyası halinde S3 uyumlu bir nesne depolama (Object Storage) alanına kaydedilir.
2. **Kalıcı Hacim (PV) Yedeklemesi:** Konteynerlerin verilerini barındıran diskler ya bulut sağlayıcısının (AWS EBS, GCP Persistent Disk vb.) disk snapshot yeteneğiyle ya da **Kopia/Restic** entegrasyonuyla dosya sistemi düzeyinde kopyalanarak yedeklenir.

> [!WARNING]
> **etcd vs. Velero:** Velero, etcd'nin disk snapshot'ını (veri tabanı yedeğini) almaz; bunun yerine nesne bazlı (logical) yedekleme yapar. Velero, tek tek nesneleri kurtarmak veya kümeleri taşımak için idealken; etcd snapshot'ı tüm master arızalarında etcd'yi kurtarmak için gereklidir. İki yedekleme stratejisi birbirini tamamlar.

---

## 2. Velero CLI ve Server Kurulumu

Velero sunucusunu kümenize kurmadan önce yerel makinenize CLI aracını yüklemelisiniz:

```bash
# Linux CLI kurulumu
curl -L https://github.com/vmware-tanzu/velero/releases/download/v1.14.0/velero-v1.14.0-linux-amd64.tar.gz | tar xz
sudo mv velero /usr/local/bin/
```

### AWS S3 Uyumlu Object Storage (MinIO, AWS S3 vb.) Üzerine Kurulum

```bash
# 1. AWS Credentials dosyasını hazırlayın (credentials-velero)
# [default]
# aws_access_key_id = S3_ACCESS_KEY
# aws_secret_access_key = S3_SECRET_KEY

# 2. Velero sunucusunu kurun (Node Agent dahil - Restic/Kopia dosya sistemi yedeği için)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups-company \
  --secret-file ./credentials-velero \
  --backup-location-config region=eu-west-1 \
  --snapshot-location-config region=eu-west-1 \
  --use-node-agent # Persistent Volume yedekleme desteğini aktif eder
```

### Google Cloud Storage (GCS) ile Kurulum

```bash
velero install \
  --provider gcp \
  --plugins velero/velero-plugin-for-gcp:v1.9.0 \
  --bucket velero-backups-company \
  --secret-file ./gcp-service-account-key.json
```

---

## 3. Manuel Yedek (Backup) Alma Komutları

```bash
# 1. Kümenin tamamını yedekleme
velero backup create full-backup-$(date +%Y%m%d)

# 2. Sadece belirli bir Namespace'i 30 gün saklanacak (TTL) şekilde yedekleme
velero backup create production-backup \
  --include-namespaces production \
  --ttl 720h # 720 saat (30 gün) sonra otomatik silinir

# 3. Belirli etiketlere (Labels) sahip podları yedekleme
velero backup create api-backup \
  --selector app=finans-api \
  --include-namespaces production

# 4. PV disk verilerini Kopia/Restic dosya sistemi entegrasyonuyla yedekleme
velero backup create volume-backup \
  --include-namespaces production \
  --default-volumes-to-fs-backup

# 5. Yedek durumunu izleme
velero backup get
velero backup describe production-backup
velero backup logs production-backup
```

---

## 4. Zamanlanmış Düzenli Yedekleme (Schedules)

Yedekleme işlemlerini otomatize etmek için cron formatında zamanlanmış görevler oluşturabilirsiniz:

```bash
# Her gün gece yarısı (00:00) production ortamını yedekle
velero schedule create gunluk-production-yedek \
  --schedule="0 0 * * *" \
  --include-namespaces production \
  --default-volumes-to-fs-backup

# Oluşturulan zamanlamaları görüntüleyin
velero schedule get
```

---

## 5. Geri Yükleme (Restore) İşlemleri

```bash
# 1. Namespace geri yükleme
velero restore create \
  --from-backup production-backup \
  --include-namespaces production

# 2. Farklı bir Namespace'e geri yükleme (Çakışmaları önlemek için)
velero restore create \
  --from-backup production-backup \
  --namespace-mappings production:production-yedekten-donulen

# 3. Sadece belirli bir kaynağı (Örn: Deployments) etikete göre kurtarma
velero restore create \
  --from-backup production-backup \
  --include-resources deployments \
  --selector app=finans-api

# 4. Geri yükleme durumunu kontrol edin
velero restore get
velero restore describe <RESTORE_ADI>
```

---

## 6. Kümeler Arası Canlı Göç (Cluster Migration)

Uygulamalarınızı eski bir Kubernetes kümesinden yeni bir kümeye taşımak için Velero'yu köprü olarak kullanabilirsiniz:

```bash
# 1. Kaynak (Eski) kümede en güncel verilerle yedek alın
velero backup create goc-yedeği \
  --include-namespaces production \
  --default-volumes-to-fs-backup

# 2. Hedef (Yeni) kümede Velero'yu kurun ve AYNI S3/Object Storage bucket'ını hedefleyin
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups-company \
  --backup-location-config region=eu-west-1

# 3. Yedeğin yeni kümede göründüğünü doğrulayın
velero backup get # listede 'goc-yedeği' görünmelidir

# 4. Hedef kümede geri yükleme işlemini tetikleyin
velero restore create \
  --from-backup goc-yedeği
```

---

## 7. Çoklu Yedek Depolama Hedefleri (Backup Storage Locations)

Velero, aynı anda birden fazla object storage veya farklı cloud sağlayıcılarına yedek almanıza izin verir. Bu durum felaket kurtarma senaryoları için ek yedeklilik sağlar:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [velero_ile_yedekleme_manifest_1.yaml](../Manifests/04_infrastructure/velero_ile_yedekleme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

```bash
# İkincil yedek konumuna manuel yedek tetikleme
velero backup create dr-backup \
  --storage-location backup-yedek-hedef \
  --include-namespaces production
```

---

## Özet

Velero, hem Kubernetes durumsuz nesnelerini hem de kalıcı depolama alanlarını (PV) yedekleyen ve taşıyan esnek bir felaket kurtarma aracıdır. **Cron schedule** ile otomatikleştirilmiş yedek planları kurgulamak, **Kopia/Restic** ile disk verilerini taşımak ve alınan yedeklerin doğruluğunu belirli aralıklarla test etmek, altyapı güvenliğinin en önemli adımlarıdır.
