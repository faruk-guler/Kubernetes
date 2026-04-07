# Velero — Felaket Kurtarma ve Yedekleme

## 2.1 Velero Nedir?

**Velero**, Kubernetes cluster kaynaklarını (YAML nesneleri) ve kalıcı depolama verilerini (PV) yedekleyen ve geri yükleyen açık kaynak bir araçtır. Tüm cluster çöktüğünde dakikalar içinde geri dönüşü mümkün kılar.

## 2.2 Kurulum (AWS S3 ile)

```bash
# Velero CLI kurulumu
curl -fsSL -o velero-v1.14.0-linux-amd64.tar.gz \
  https://github.com/vmware-tanzu/velero/releases/download/v1.14.0/velero-v1.14.0-linux-amd64.tar.gz
tar -xvf velero-v1.14.0-linux-amd64.tar.gz
mv velero-v1.14.0-linux-amd64/velero /usr/local/bin/

# Velero sunucu kurulumu (AWS S3)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket my-velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=eu-west-1 \
  --snapshot-location-config region=eu-west-1 \
  --use-volume-snapshots=true

# credentials-velero içeriği:
# [default]
# aws_access_key_id=<KEY>
# aws_secret_access_key=<SECRET>
```

## 2.3 Yedekleme

```bash
# Belirli namespace yedekle
velero backup create prod-backup-$(date +%Y%m%d) \
  --include-namespaces production \
  --wait

# Tüm cluster yedekle
velero backup create full-cluster-backup \
  --include-namespaces "*" \
  --exclude-namespaces kube-system,velero \
  --wait

# Yedek durumunu kontrol et
velero backup describe prod-backup-20260402
velero backup logs prod-backup-20260402

# Yedek listesi
velero backup get
```

## 2.4 Zamanlanmış Yedekleme

```bash
# Her gece 02:00'de yedek al, 30 gün sakla
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces production,staging \
  --ttl 720h       # 30 gün

# Haftalık tam yedek
velero schedule create weekly-full \
  --schedule="0 1 * * 0" \
  --ttl 2160h      # 90 gün
```

## 2.5 Geri Yükleme

```bash
# Son yedekten geri yükle
velero restore create --from-backup prod-backup-20260402

# Sadece belirli kaynaklar
velero restore create \
  --from-backup prod-backup-20260402 \
  --include-resources deployments,services,configmaps

# Farklı namespace'e geri yükle
velero restore create \
  --from-backup prod-backup-20260402 \
  --namespace-mappings production:production-restored

# Geri yükleme durumunu izle
velero restore describe <restore-adı>
```

## 2.6 Olağanüstü Durum Senaryosu (DR Testi)

```bash
# 1. Yedek al
velero backup create pre-dr-test --include-namespaces production

# 2. (Test için) namespace'i sil
kubectl delete namespace production

# 3. Geri yükle
velero restore create dr-test --from-backup pre-dr-test

# 4. Doğrula
kubectl get pods -n production
kubectl get pvc -n production
```

> [!CAUTION]
> DR testini düzenli yapın! Yedek almak yeterli değil — geri yüklemenin çalıştığından emin olmak gerekir. Aylık DR tatbikatı production güvenliğinin vazgeçilmez bir parçasıdır.

---
