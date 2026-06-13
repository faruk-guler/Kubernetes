# etcd Felaket Kurtarma (Disaster Recovery & Quorum Loss)

Kubernetes kümesinin tüm durumu (state) `etcd` Key-Value veritabanında tutulur. etcd cluster'ı çökünce K8s API yanıt vermez, hiçbir işlem yapılamaz. Bu belge felaket senaryolarını ve kurtarma adımlarını kapsar.

---

## etcd Raft Konsensüs ve Quorum

Raft algoritması **(N/2)+1 çoğunluk (Quorum)** prensibine göre çalışır:

| Cluster Boyutu | Tolere Edilen Arıza | Quorum |
|:--------------:|:-------------------:|:------:|
| 1 node | 0 | 1 |
| 3 node | 1 | 2 |
| 5 node | 2 | 3 |
| 7 node | 3 | 4 |

> **Örnek:** 3 node'luk etcd cluster'da 2 node ölürse → Quorum yok → K8s API kilitlenir, `kubectl get nodes` hata verir.

---

## Sağlıklı Ortamda Yedek Alma

```bash
export ETCDCTL_API=3

# Snapshot al
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd-$(date +%Y%m%d-%H%M).db

# Snapshot doğrula
etcdctl --write-out=table snapshot status /backup/etcd-*.db
```

### Otomatik Yedekleme CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 */6 * * *"    # Her 6 saatte bir
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
          tolerations:
          - key: node-role.kubernetes.io/control-plane
            effect: NoSchedule
          containers:
          - name: etcd-backup
            image: registry.k8s.io/etcd:3.5.x
            command:
            - /bin/sh
            - -c
            - |
              SNAPSHOT=/backup/etcd-$(date +%Y%m%d-%H%M).db
              etcdctl \
                --endpoints=https://127.0.0.1:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key \
                snapshot save $SNAPSHOT
              # Eski yedekleri temizle (30 günden eski)
              find /backup -name "etcd-*.db" -mtime +30 -delete
              echo "Backup done: $SNAPSHOT"
            volumeMounts:
            - name: etcd-certs
              mountPath: /etc/kubernetes/pki/etcd
              readOnly: true
            - name: backup-vol
              mountPath: /backup
          volumes:
          - name: etcd-certs
            hostPath:
              path: /etc/kubernetes/pki/etcd
          - name: backup-vol
            persistentVolumeClaim:
              claimName: etcd-backup-pvc
          restartPolicy: OnFailure
```

---

## Senaryo 1: Quorum Kaybı (2 Node Çöktü, 1 Kaldı)

3 master node'dan 2'si kalıcı arıza verdi. Kalan 1 node'da K8s API yanıt vermiyor.

```bash
# ADIM 1: Tüm control plane bileşenlerini durdur
sudo systemctl stop kubelet
# kube-apiserver, etcd, kube-controller-manager static pod manifestlerini kaldır
sudo mv /etc/kubernetes/manifests/*.yaml /tmp/k8s-manifests-backup/

# ADIM 2: Bozuk etcd verisini yedekle ve kaldır
sudo mv /var/lib/etcd /var/lib/etcd.bak

# ADIM 3: Tek node restore (Single-Node mode)
etcdctl snapshot restore /backup/etcd-latest.db \
  --name master-1 \
  --initial-cluster "master-1=https://10.0.0.11:2380" \
  --initial-cluster-token "etcd-cluster-restore-$(date +%s)" \
  --initial-advertise-peer-urls "https://10.0.0.11:2380" \
  --data-dir=/var/lib/etcd

# Sahipliği düzelt
sudo chown -R etcd:etcd /var/lib/etcd

# ADIM 4: Control plane'i geri getir
sudo mv /tmp/k8s-manifests-backup/*.yaml /etc/kubernetes/manifests/
sudo systemctl start kubelet

# ADIM 5: Doğrula
kubectl get nodes
kubectl get pods -n kube-system

# ADIM 6: Yeni master node'ları ekle
kubeadm token create --print-join-command
# Diğer node'larda: kubeadm join <control-plane>:6443 --token ... --control-plane
```

> [!CAUTION]
> `snapshot restore` komutunda `--initial-cluster` içine sadece TEK node yazın. Birden fazla node yazarsanız restore başarısız olur. Diğer node'lar restore sonrası normal join ile eklenir.

---

## Senaryo 2: Tüm etcd Verisi Bozuldu (Data Corruption)

```bash
# Etcd'nin durumunu kontrol et
etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key

# Üye listesi
etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key
```

### 3 Node'lu Cluster'da Koordineli Restore

```bash
# HER MASTER NODE'DA aynı snapshot kullanılmalı

# master-1'de:
etcdctl snapshot restore /backup/etcd-latest.db \
  --name master-1 \
  --initial-cluster "master-1=https://10.0.0.11:2380,master-2=https://10.0.0.12:2380,master-3=https://10.0.0.13:2380" \
  --initial-cluster-token "etcd-cluster-restore" \
  --initial-advertise-peer-urls "https://10.0.0.11:2380" \
  --data-dir=/var/lib/etcd

# master-2'de:
etcdctl snapshot restore /backup/etcd-latest.db \
  --name master-2 \
  --initial-cluster "master-1=https://10.0.0.11:2380,master-2=https://10.0.0.12:2380,master-3=https://10.0.0.13:2380" \
  --initial-cluster-token "etcd-cluster-restore" \
  --initial-advertise-peer-urls "https://10.0.0.12:2380" \
  --data-dir=/var/lib/etcd

# master-3'de: (aynı pattern, --name master-3, --initial-advertise-peer-urls 10.0.0.13)

# Tüm node'larda kubelet'i yeniden başlat
sudo systemctl restart kubelet
```

---

## Senaryo 3: Yanlışlıkla Silinen Namespace/Resource

etcd snapshot yerine sadece Velero ile obje geri yükleme:

```bash
# Namespace silindi
velero restore create --from-backup daily-backup-2026-05-04 \
  --include-namespaces production \
  --restore-volumes=true

# Tek bir Deployment geri yükle
velero restore create --from-backup daily-backup-2026-05-04 \
  --include-namespaces production \
  --include-resources deployments \
  --selector app=api-server
```

---

## etcd Sağlık Metrikleri

```promql
# etcd Raft proposal başarısızlıkları
rate(etcd_server_proposals_failed_total[5m]) > 0

# etcd lider değişimi (instability göstergesi)
rate(etcd_server_leader_changes_seen_total[1h]) > 2

# etcd disk yazma gecikmesi (>100ms alarm)
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) > 0.1

# etcd gRPC yanıt süresi
histogram_quantile(0.99, rate(etcd_grpc_unary_requests_duration_seconds_bucket[5m])) > 0.5
```

> [!TIP]
> etcd için SSD disk zorunludur. HDD veya yüksek I/O latency'li disk, Raft leader timeout'larına ve cluster instability'ye yol açar. `etcd_disk_wal_fsync_duration_seconds` p99 değerini daima izleyin — 10ms altında tutmaya çalışın.
