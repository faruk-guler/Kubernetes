# CloudNativePG — Kubernetes'te PostgreSQL Yönetimi

Eskiden "veritabanı Kubernetes üzerinde çalışmaz" denirdi. 2026'da **Operator Pattern** sayesinde PostgreSQL yönetmek, managed service kullanmaktan daha güvenli ve ekonomik hale gelmiştir.

## 2.1 CloudNativePG Nedir?

**CloudNativePG (CNPG)**, PostgreSQL'in Kubernetes'te çalışması için tasarlanmış CNCF projesidir. Bir veritabanı yöneticisinin (DBA) tüm operasyonel bilgisini koda dönüştürür:

- Otomatik failover (Primary pod çökerse replica otomatik primary olur)
- Otomatik yedekleme (WAL archiving + base backup)
- Rolling upgrades (PostgreSQL major version yükseltme)
- Read replica yönetimi
- Connection pooling (PgBouncer entegrasyonu)

## 2.2 Kurulum

```bash
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.25.0.yaml

# Doğrulama
kubectl get deployment -n cnpg-system
```

## 2.3 Yüksek Erişilebilir PostgreSQL Cluster

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-prod
  namespace: production
spec:
  instances: 3                    # 1 Primary + 2 Replica
  imageName: ghcr.io/cloudnative-pg/postgresql:16.3

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"

  storage:
    size: 50Gi
    storageClass: longhorn-replicated

  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "2000m"

  monitoring:
    enablePodMonitor: true         # Prometheus entegrasyonu

  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: "s3://my-backup-bucket/postgres"
      s3Credentials:
        accessKeyId:
          name: aws-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-credentials
          key: SECRET_ACCESS_KEY
```

## 2.4 Yedekleme ve Geri Yükleme

```bash
# Manuel yedek al
kubectl cnpg backup postgres-prod -n production

# Yedek listesi
kubectl get backup -n production

# Belirli bir zamana geri dönme (PITR)
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restored
  namespace: production
spec:
  instances: 1
  bootstrap:
    recovery:
      source: postgres-prod
      recoveryTarget:
        targetTime: "2026-04-01 03:00:00"
  externalClusters:
  - name: postgres-prod
    barmanObjectStore:
      destinationPath: "s3://my-backup-bucket/postgres"
      s3Credentials:
        ...
EOF
```

## 2.5 Bağlantı Yönetimi

CNPG, Primary ve Replica için ayrı servisler oluşturur:

```bash
# Servisler
kubectl get svc -n production | grep postgres
# postgres-prod-rw    → Primary (okuma + yazma)
# postgres-prod-r     → Replica (sadece okuma)
# postgres-prod-ro    → Round-robin replica

# Bağlantı bilgilerini al
kubectl get secret postgres-prod-app -n production -o jsonpath='{.data.uri}' | base64 -d
```

## 2.6 Neden Kubernetes'e Taşımalı?

| Kriter | Managed DB (RDS) | CloudNativePG |
|:---|:---|:---|
| Maliyet | Yüksek ($$$) | Düşük (altyapı maliyeti) |
| Kontrol | Sınırlı | Tam |
| Yedekleme | Otomatik | Otomatik (S3/GCS/Az) |
| Failover | Otomatik | Otomatik (daha hızlı) |
| GitOps | âŒ | ✅ |
| Multi-cloud | âŒ | ✅ |

> [!TIP]
> Redis için **Redis Operator**, MongoDB için **Percona Operator**, MySQL için **Vitess** 2026'nın önerilen operator'larıdır.

---
