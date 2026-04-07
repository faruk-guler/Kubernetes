# etcd Felaket Kurtarma (Disaster Recovery & Quorum Loss)

Kubernetes kümesinin tüm hafızası ve durumu `etcd` Key-Value veritabanında tutulur. Velero sadece "objeleri" (deployment vb.) yedekler; fakat altyapıda **3 node veya 5 node'dan oluşan etcd cluster (Raft Protocol)** tamamen yarıdan fazla düğümünü kaybederse (Quorum Loss), küme tamamen çöker. "Black Belt" K8s eylemi budur.

---

## 8.1 Etcd'nin Çalışma Prensibi (Raft)

Raft algoritması $\frac{N}{2}+1$ (Çoğunluk / Quorum) prensibine göre çalışır.
- 3 Etcd Node varsa, en az **2** tanesi ayakta olmak zorundadır.
- 2 Node ölürse Quorum bozulur. Kalan 1 Node sağlıklı olsa bile veritabanı KİLİTLENİR. K8s API hizmet vermeyi keser (`kubectl get nodes -> Error`).

---

## 8.2 Sağlıklı Ortamda etcdctl ile Yedek Alma (Snapshot)

Her gün en az 1 kez fiziksel /etc/etcd düzeyinde yedek alınmalıdır.

```bash
# Etcdctl v3 API kullanılmalı
export ETCDCTL_API=3

# Master Node üzerinden snapshot alma:
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/snapshot-db.db

# Durumu Doğrulama
etcdctl --write-out=table snapshot status /tmp/snapshot-db.db
```

---

## 8.3 Kötü Senaryo: Quorum Kaybı (Cluster Çöktü)

3 Master node'dan 2'si elektrik kesintisinde donanım arızası verdi (ve geri gelmiyor). Kalan sunucudaki K8s API yanıt vermiyor. Kümeyi tek bir Node (Single-Node) olarak zorla (Force) yeniden başlatacağız ve diğer Node'ları tekrar ekleyeceğiz.

### Adım 1: Etcd ve K8s Bileşenlerini Durdurun
Çöken ve ayaktaki kalan tüm sistemlerde:
```bash
sudo systemctl stop kubelet
sudo rm -rf /etc/kubernetes/manifests/kube-apiserver.yaml
# (Yada RKE2 ise: sudo systemctl stop rke2-server)
```

### Adım 2: Hasarlı Veriyi Taşıyın (Backup Dizini)
Artık geçersiz olan Quorum verisini güvenli dizine alın:
```bash
sudo mv /var/lib/etcd /var/lib/etcd.bak
```

### Adım 3: Snapshot'tan Tekil Küme Restore (Önemli Adım)
Raft Quorum'unu by-pass edip, yeni baştan 1 node'luk yepyeni ama eski state'e sahip veritabanı başlatıyoruz:

```bash
etcdctl snapshot restore /tmp/snapshot-db.db \
  --name master-1 \
  --initial-cluster "master-1=https://10.0.0.11:2380" \
  --initial-cluster-token "etcd-cluster-new" \
  --initial-advertise-peer-urls "https://10.0.0.11:2380" \
  --data-dir=/var/lib/etcd
```

### Adım 4: Sistemi Yeniden Başlatın
```bash
# Kube-apiserver yaml'ı ve/veya kubelet servisini tekrar geri getirin
sudo systemctl start kubelet

# Kontrol API (API ayağa kalkmış olmalı)
kubectl get pods -n kube-system
```

Yepyeni ve eski verileri eksiksiz taşıyan 1 Node'luk sağlıklı bir etcd + k8s cluster var. Şimdi yeni Master (Etcd) Node'larını normal yöntemle (`kubeadm join` veya `rke2 server join`) ekleyerek 3 Node yapısına tekrar geri dönebilirsiniz.

> [!CAUTION]
> Asla restore komutunu çalıştırırken `initial-cluster` içerisine birden fazla makine adı yazmayın! Restore işlemi daima *1 Node üzerinde Single Node Mode*'da başlatılır, diğerleri sonradan veri senkronizasyonu ile katılır.

---
*← [Ana Sayfa](../README.md)*
