# etcd Yedekleme ve Geri Yükleme

> [!CAUTION]
> etcd, tüm cluster state'ini saklar. etcd olmadan cluster kurtarılamaz. **Düzenli yedekleme hayati önem taşır.**

---

## etcd Neden Özel?

etcd'de şunlar saklanır: tüm YAML tanımları, Secret'lar, ConfigMap'ler, RBAC kuralları, Deployment state'leri... Kısaca cluster'ın tamamı.

```bash
# etcd pod'unu bul (kubeadm kurulumunda)
kubectl get pods -n kube-system | grep etcd

# etcd'nin çalışıp çalışmadığını kontrol et
kubectl exec -n kube-system etcd-k8s-master -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health
```

## Manuel Snapshot Alma (kubeadm)

Sertifika yolları kubeadm kurulumunda `/etc/kubernetes/pki/etcd/` altındadır:

```bash
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db
```

### Snapshot Doğrulama

```bash
ETCDCTL_API=3 etcdctl \
  --write-out=table \
  snapshot status /backup/etcd-20260402-140000.db
```

Çıktı örneği:
```
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
| bd9a9b75 |    45678 |       1234 |     4.5 MB |
+----------+----------+------------+------------+
```

## Zamanlanmış Yedekleme (CronJob)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 */6 * * *"   # 6 saatte bir
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
          tolerations:
          - effect: NoSchedule
            operator: Exists
          containers:
          - name: etcd-backup
            image: bitnami/etcd:3.5
            command:
            - /bin/sh
            - -c
            - |
              etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db
              find /backup -name "*.db" -mtime +7 -delete  # 7 günden eski sil
            env:
            - name: ETCDCTL_API
              value: "3"
            - name: ETCDCTL_ENDPOINTS
              value: "https://127.0.0.1:2379"
            - name: ETCDCTL_CACERT
              value: /etc/kubernetes/pki/etcd/ca.crt
            - name: ETCDCTL_CERT
              value: /etc/kubernetes/pki/etcd/healthcheck-client.crt
            - name: ETCDCTL_KEY
              value: /etc/kubernetes/pki/etcd/healthcheck-client.key
            volumeMounts:
            - name: etcd-pki
              mountPath: /etc/kubernetes/pki/etcd
              readOnly: true
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: etcd-pki
            hostPath:
              path: /etc/kubernetes/pki/etcd
          - name: backup-storage
            persistentVolumeClaim:
              claimName: etcd-backup-pvc
          restartPolicy: OnFailure
```

## Geri Yükleme (Restore)

> [!CAUTION]
> Geri yükleme işlemi cluster'ı durdurur. Üretimde önce test ortamında deneyin.

```bash
# 1. API Server ve etcd'yi durdur (Static Pod'ları taşıyarak)
mv /etc/kubernetes/manifests/etcd.yaml /tmp/
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# 2. Restore işlemi (yeni dizine)
ETCDCTL_API=3 etcdctl \
  --data-dir=/var/lib/etcd-from-backup \
  snapshot restore /backup/etcd-20260402-140000.db

# 3. etcd manifesto'sunda --data-dir'i güncelle
sed -i 's|/var/lib/etcd|/var/lib/etcd-from-backup|g' /tmp/etcd.yaml

# 4. Static Pod'ları geri getir
mv /tmp/etcd.yaml /etc/kubernetes/manifests/
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# 5. Cluster'ın ayağa kalkmasını bekle
kubectl get nodes --watch
```

## RKE2 Özel ETCD Operasyonları

RKE2'de etcd yedekleri `/var/lib/rancher/rke2/server/db/snapshots` altında tutulur:

```bash
# Manuel snapshot al
rke2 etcd-snapshot save --name pre-upgrade-$(date +%Y%m%d)

# Snapshot listesi
rke2 etcd-snapshot ls

# Quorum kaybı — Cluster Reset
systemctl stop rke2-server
rke2 server --cluster-reset

# Snapshot'tan restore
systemctl stop rke2-server   # Tüm server node'larda
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/pre-upgrade-20260402
systemctl start rke2-server  # Sadece birinci master'da

# Diğer master node'larda eski db sil ve yeniden başlat
rm -rf /var/lib/rancher/rke2/server/db
systemctl start rke2-server
```

> [!WARNING]
> RKE2 reset işlemi sonrası `/var/lib/rancher/rke2/server/db/reset-flag` dosyası oluşur. Bu dosya normal başlatmada otomatik silinir.

---

## etcd Küme Sağlığı ve Proaktif İzleme (Monitoring)

Bir cluster'ın kararlılığı, etcd kümesinin sağlığına doğrudan bağlıdır. Yalnızca yedek almak yetmez; etcd kümesini proaktif (önleyici) olarak izlemek, felaket senaryolarını gerçekleşmeden önler.

### 1. Komut Satırı ile etcd Sağlık Kontrolü (CLI Diagnostics)

Kubeadm ortamında etcd pod'unun içinde veya etcdctl kurulu olan control plane düğümünde şu tanı komutlarını çalıştırın:

```bash
# etcd kümesindeki tüm üyelerin listesi ve durumları
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  member list --write-out=table

# Tüm küme düğümlerinin sağlık durumu (Cluster-wide Health Check)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  --cluster \
  endpoint health --write-out=table

# Veritabanı boyutları ve fragmantasyon oranları (status)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  --cluster \
  endpoint status --write-out=table
```

> [!TIP]
> **endpoint status** çıktısındaki **DB SIZE** alanı varsayılan olarak maksimum **2GB** (veya konfigüre edilmişse 8GB) kotayı aşmamalıdır. Eğer aşarsa etcd `alarm` durumuna geçer ve yazma işlemlerini kapatır. Bu durumda `defrag` komutu çalıştırılmalıdır.

---

### 2. Kritik Prometheus Metrikleri ve Uyarı Eşikleri

etcd, `/metrics` endpoint'i üzerinden Prometheus formatında binlerce metrik sunar. Grafana panolarınızda ve Alertmanager kurallarınızda mutlaka izlemeniz gereken 3 altın metrik:

| Metrik Adı | Önem Derecesi | Uyarı Eşiği | Açıklama |
| :--- | :--- | :--- | :--- |
| `etcd_server_has_leader` | 🔴 Kritik | `0` (Lidersiz) | Kümede aktif bir lider olup olmadığını belirtir. `0` ise küme çökmüştür, yazma/okuma yapılamaz. |
| `etcd_disk_wal_write_duration_seconds` | 🟡 Yüksek | `> 0.01` (10ms) | Diske Write-Ahead Log (WAL) yazma süresi. Yüksek değerler yavaş diskleri (I/O darboğazı) gösterir ve quorum kaybına yol açabilir. |
| `etcd_network_peer_round_trip_time_seconds` | 🟡 Yüksek | `> 0.1` (100ms) | etcd düğümleri arasındaki ağ gecikmesi. Yüksek ağ gecikmesi lider seçimlerinin sürekli tetiklenmesine (instability) neden olur. |

Bu metrikleri Prometheus üzerinde izlemek için etcd pod'larının `prometheus.io/scrape: "true"` annotation'larına ve ilgili certificate/key dosyalarıyla yetkilendirilmiş bir scrape config'e sahip olması gerekir.
