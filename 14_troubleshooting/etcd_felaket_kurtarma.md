# etcd Felaket Kurtarma (etcd Disaster Recovery & Quorum Loss)

Kubernetes kümesinin tüm durumu (state) `etcd` Key-Value veritabanında tutulur. etcd kümesi (cluster) çöktüğünde Kubernetes API Server yanıt vermeyi keser ve küme üzerinde hiçbir işlem yapılamaz.

Bu bölümde, etcd kümesindeki konsensüs (çoğunluk) kaybı, veri bozulması (data corruption) gibi felaket senaryolarını ve bu durumlardan kurtarma (recovery) adımlarını inceleyeceğiz.

---

## 1. Raft Konsensüs Algoritması ve Quorum (Çoğunluk) Mekanizması

etcd, düğümler arasında veri tutarlılığını sağlamak için **Raft** konsensüs algoritmasını kullanır. Kümenin kararlar alabilmesi ve yazma işlemlerini gerçekleştirebilmesi için aktif düğüm sayısının **(N/2)+1 çoğunluğa (Quorum)** sahip olması zorunludur:

| Toplam etcd Düğüm Sayısı (N) | Tolere Edilebilen Arızalı Düğüm Sayısı | Gerekli Quorum (Çoğunluk) Sayısı |
|:---:|:---:|:---:|
| 1 | 0 | 1 |
| 3 | 1 | 2 |
| 5 | 2 | 3 |
| 7 | 3 | 4 |

> [!IMPORTANT]
> **Örnek Senaryo:** 3 master düğümlü bir kümede, 2 master sunucusu kalıcı olarak çökerse, geriye 1 düğüm kalır. Quorum sayısı 2 olması gerektiğinden çoğunluk kaybedilir. Kubernetes API sunucusu kilitlenir ve `kubectl` komutları hata vermeye başlar.

---

## 2. Senaryo 1: Quorum (Çoğunluk) Kaybı Kurtarma

3 Master düğümünden 2'sinin tamamen çöktüğünü ve geriye sadece 1 çalışan Master düğümünün kaldığını varsayalım. Kalan bu tek düğüm üzerinden kümeyi ayağa kaldırma adımları:

### Adım 1: Control Plane Bileşenlerini Durdurun

Çalışan tek master sunucusunda `kubelet` servisini durdurun ve statik pod manifestlerini yedekleyin:

```bash
sudo systemctl stop kubelet
sudo mkdir -p /tmp/k8s-manifests-backup
sudo mv /etc/kubernetes/manifests/*.yaml /tmp/k8s-manifests-backup/
```

### Adım 2: Mevcut Bozuk etcd Veri Dizinini Yedekleyin

```bash
sudo mv /var/lib/etcd /var/lib/etcd.corrupted
```

### Adım 3: Tek Düğümlü (Single-Node) Olarak Restore Edin

Elimizdeki en güncel sağlıklı etcd snapshot dosyasını kullanarak, veritabanını sadece bu sunucu aktif olacak şekilde restore edin:

```bash
export ETCDCTL_API=3

etcdctl snapshot restore /backup/etcd-latest.db \
  --name k8s-master-01 \
  --initial-cluster "k8s-master-01=https://192.168.10.10:2380" \
  --initial-cluster-token "etcd-recovery-token" \
  --initial-advertise-peer-urls "https://192.168.10.10:2380" \
  --data-dir=/var/lib/etcd

# Dosya yetkilerini düzenleyin
sudo chown -R etcd:etcd /var/lib/etcd
```

> [!CAUTION]
> `--initial-cluster` parametresine **yalnızca hayatta kalan tek düğümün** bilgisini yazmalısınız. Diğer çöken master düğümlerini buraya eklemek restore işleminin başarısız olmasına yol açar. Diğer master'lar daha sonra sıfırdan join edilerek eklenecektir.

### Adım 4: Master Servislerini Tekrar Başlatın

```bash
sudo mv /tmp/k8s-manifests-backup/*.yaml /etc/kubernetes/manifests/
sudo systemctl start kubelet
```

### Adım 5: Küme Durumunu Doğrulayın

```bash
kubectl get nodes
kubectl get pods -A
# Küme tek master ile ayağa kalkmış olmalıdır.
```

---

## 3. Senaryo 2: Tüm Kümede Veri Bozulması (Data Corruption)

Eğer etcd veritabanı tüm düğümlerde bozulduysa, tüm master düğümlerinde koordineli bir şekilde aynı yedek dosyasından geri yükleme yapılması gerekir:

```bash
# TÜM MASTER DÜĞÜMLERİNDE:
# 1. Kubelet'i durdurun ve manifestleri taşıyın.
# 2. /var/lib/etcd dizinini silin veya taşıyın.

# DÜĞÜM 1 (k8s-master-01) Üzerinde Restore:
etcdctl snapshot restore /backup/etcd-latest.db \
  --name k8s-master-01 \
  --initial-cluster "k8s-master-01=https://192.168.10.10:2380,k8s-master-02=https://192.168.10.11:2380,k8s-master-03=https://192.168.10.12:2380" \
  --initial-cluster-token "etcd-global-restore" \
  --initial-advertise-peer-urls "https://192.168.10.10:2380" \
  --data-dir=/var/lib/etcd

# DÜĞÜM 2 (k8s-master-02) Üzerinde Restore:
etcdctl snapshot restore /backup/etcd-latest.db \
  --name k8s-master-02 \
  --initial-cluster "k8s-master-01=https://192.168.10.10:2380,k8s-master-02=https://192.168.10.11:2380,k8s-master-03=https://192.168.10.12:2380" \
  --initial-cluster-token "etcd-global-restore" \
  --initial-advertise-peer-urls "https://192.168.10.11:2380" \
  --data-dir=/var/lib/etcd

# (Aynı işlem Düğüm 3 için de kendi IP adresi ve ismiyle tekrarlanır.)

# TÜM DÜĞÜMLERDE:
# 3. Manifest dosyalarını tekrar /etc/kubernetes/manifests altına taşıyın.
# 4. Kubelet servisini başlatın: sudo systemctl start kubelet
```

---

## 4. Senaryo 3: Yanlışlıkla Silinen Nesneler (Namespace/Deployment)

Eğer fiziksel bir çökme yoksa, sadece bir geliştirici yanlışlıkla kritik bir Namespace veya Deployment sildiyse, tüm etcd veritabanını geri yüklemek yerine **Velero** kullanarak nesne bazlı (granular) geri yükleme yapılması önerilir. etcd restore işlemi geçmişe döneceğinden son yedekten sonraki tüm yeni işlemleri de silecektir.

```bash
# 1. Silinen namespace'i sadece o namespace'i hedefleyerek Velero yedeğinden kurtarın
velero restore create --from-backup gunluk-yedek-2026-07-11 \
  --include-namespaces production \
  --restore-volumes=true

# 2. Sadece belirli bir Deployment'ı etikete göre kurtarın
velero restore create --from-backup gunluk-yedek-2026-07-11 \
  --include-namespaces production \
  --include-resources deployments \
  --selector app=finans-api
```

---

## 5. etcd Sağlığı İçin Kritik Prometheus / Alertmanager Metrikleri

etcd kümesinin durumunu önceden izlemek ve felaketlerin önüne geçmek için Grafana/Prometheus üzerinde şu PromQL alarmları kurgulanmalıdır:

```promql
# 1. Kümede Lider Yok Alarmı (Kritik - Leaderless Cluster)
# Sonuç 0 ise küme çökmüştür.
etcd_server_has_leader == 0

# 2. Sık Lider Değişimi Alarmı (Instability - Ağ veya Disk sorunu)
# 1 saatte 3'ten fazla lider değişimi kararsızlık göstergesidir.
rate(etcd_server_leader_changes_seen_total[1h]) > 3

# 3. Disk Yazma Gecikmesi Alarmı (WAL Write Latency)
# WAL diske yazma süresinin p99 değerinin 10ms (0.01s) üzerinde olması disk darboğazını gösterir.
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) > 0.01
```

> [!TIP]
> **Disk Performansı:** etcd veritabanı her yazma işleminde diske senkron (fsync) yazar. Bu nedenle etcd sunucularında **SSD/NVMe** disk kullanımı zorunludur. Paylaşımlı yavaş ağ diskleri (örneğin AWS standard EBS) etcd düğümlerinin zaman aşımına uğramasına ve küme çökmelerine yol açar.

---

## Özet

etcd felaket kurtarma operasyonları, Raft quorum kurallarına dayanır. Çoğunluk kaybedildiğinde, eldeki sağlıklı bir yedekle tek master düğümü üzerinden (**Single-Node restore**) küme ayağa kaldırılabilir. Kümenin sağlığını korumak için disk yazma gecikmeleri (`wal_fsync`) sürekli izlenmeli ve veri bozulmalarına karşı mutlaka **Velero** gibi nesne bazlı yedekleme alternatifleri konumlandırılmalıdır.
