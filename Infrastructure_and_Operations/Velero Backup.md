# Velero — Backup & Restore

Velero, Kubernetes kaynaklarını (YAML manifest'leri) ve kalıcı disk verilerini (PV snapshot) yedekler. Cluster göçü, felaket kurtarma ve namespace geri yükleme için kullanılır.

---

## Mimari

```
Velero Server (Deployment) → Object Storage (S3/GCS/Azure Blob) → Yedek
                           → Volume Snapshots (CSI/Cloud) → Disk verisi

Yedeklenen:
  ✅ Tüm Kubernetes YAML kaynakları (Deployment, Service, ConfigMap vb.)
  ✅ PersistentVolume verileri (CSI snapshot veya Restic/Kopia ile)
  ❌ etcd snapshot değil — object-level yedek
```

---

## Kurulum

```bash
# Velero CLI kurulumu
brew install velero   # macOS
# Linux:
curl -L https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz | tar xz
sudo mv velero /usr/local/bin/

# AWS S3 ile kurulum
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups-company \
  --secret-file ./credentials-velero \
  --backup-location-config region=eu-west-1 \
  --snapshot-location-config region=eu-west-1 \
  --use-node-agent    # PV yedekleme için (Restic/Kopia)

# GCS ile
velero install \
  --provider gcp \
  --plugins velero/velero-plugin-for-gcp:v1.9.0 \
  --bucket velero-backups-company \
  --secret-file ./credentials-velero

# Azure Blob ile
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.9.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --backup-location-config storageAccount=velerostore,resourceGroup=rg-prod
```

---

## Manuel Yedek

```bash
# Tüm cluster
velero backup create full-backup-$(date +%Y%m%d)

# Belirli namespace
velero backup create prod-backup \
  --include-namespaces production \
  --ttl 720h    # 30 gün sakla

# Label ile seçici yedek
velero backup create api-backup \
  --selector app=api \
  --include-namespaces production

# PV verilerini de yedekle
velero backup create with-volumes \
  --include-namespaces production \
  --default-volumes-to-fs-backup   # Restic/Kopia ile dosya seviyesi

# Yedek durumu
velero backup get
velero backup describe prod-backup
velero backup logs prod-backup
```

---

## Zamanlanmış Yedek (Schedule)

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-production-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"    # Her gece 02:00 UTC
  template:
    includedNamespaces:
    - production
    - staging
    excludedResources:
    - events
    - events.events.k8s.io
    ttl: 720h                # 30 gün sakla
    defaultVolumesToFsBackup: true
    storageLocation: default
    volumeSnapshotLocations:
    - default
```

```bash
# Schedule yönetimi
velero schedule get
velero schedule describe daily-production-backup

# Manuel tetikle
velero backup create --from-schedule daily-production-backup
```

---

## Geri Yükleme (Restore)

```bash
# Yedekleri listele
velero backup get

# Namespace geri yükle
velero restore create \
  --from-backup prod-backup \
  --include-namespaces production

# Farklı namespace'e geri yükle (migration)
velero restore create \
  --from-backup prod-backup \
  --namespace-mappings production:production-restored

# Tek kaynak geri yükle
velero restore create \
  --from-backup prod-backup \
  --include-resources deployments \
  --selector app=api

# Restore durumu
velero restore get
velero restore describe <restore-name>
velero restore logs <restore-name>
```

---

## Cluster Göçü

```bash
# Kaynak cluster'dan yedek al
velero backup create migration-backup \
  --include-namespaces production,staging \
  --default-volumes-to-fs-backup

# Hedef cluster'a Velero kur (aynı S3 bucket'a bağla)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups-company \    # Aynı bucket!
  --backup-location-config region=eu-west-1

# Yedek görünüyor mu?
velero backup get   # migration-backup listede olmalı

# Hedef cluster'a geri yükle
velero restore create \
  --from-backup migration-backup
```

---

## BackupStorageLocation (Çoklu Hedef)

```yaml
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: secondary-backup
  namespace: velero
spec:
  provider: aws
  objectStorage:
    bucket: velero-backups-dr
    prefix: cluster-prod
  config:
    region: us-east-1    # DR bölgesi
  credential:
    name: velero-dr-credentials
    key: cloud
```

```bash
# İkincil konuma yedek al
velero backup create dr-backup \
  --storage-location secondary-backup \
  --include-namespaces production
```

---

## İzleme

```bash
# Yedek boyutu ve süresi
velero backup describe prod-backup --details

# Prometheus metrikleri
velero_backup_success_total        # Başarılı yedek sayısı
velero_backup_failure_total        # Başarısız yedek sayısı
velero_backup_duration_seconds     # Yedek süresi
velero_restore_success_total       # Başarılı restore
velero_volume_snapshot_success_total
```

> [!IMPORTANT]
> Velero yedeklerini **düzenli aralıklarla test edin** — restore etmeden yedek almanın anlamı yok. Ayda bir `velero restore create --from-backup <latest>` yapıp geri yüklemenin çalıştığını doğrulayın.

> [!WARNING]
> Velero YAML kaynaklarını yedekler ama etcd'yi değil. Control plane ve etcd için ayrıca `etcd snapshot save` yapın. İkisi birbirini tamamlar.
