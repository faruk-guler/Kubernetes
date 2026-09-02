# Felaket Kurtarma (Disaster Recovery) Runbook

Bu kılavuz, bir Kubernetes kümesinde (cluster) yaşanabilecek kritik ve acil durum senaryolarında, sistem mühendisleri ve DevOps ekipleri tarafından adım adım izlenmesi gereken felaket kurtarma (Disaster Recovery - DR) prosedürlerini içerir.

---

## 1. Hazırlık ve Önleyici Kontroller (Pre-DR Checklist)

Kriz anında kayıpları en aza indirmek için yedekleme ve denetleme adımları önceden otomatize edilmelidir:

```bash
# 1. etcd Anlık Görüntüsünü (Snapshot) Kaydetme (Günlük/Haftalık)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 2. Velero ile Uygulama ve Durum Yedekleme
velero backup create weekly-backup-$(date +%Y%m%d) \
  --include-namespaces production,staging \
  --ttl 720h

# 3. Küme Sertifika Sürelerinin Kontrolü
kubeadm certs check-expiration

# 4. etcd Üye Sağlığının Kontrolü
etcdctl member list \
  --write-out=table \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## 2. Senaryo 1: Pod CrashLoopBackOff ve OOMKilled Hataları

Bir podun sürekli çökmesi ve başlamaması durumunda izlenecek adımlar:

```bash
# 1. Pod Detaylarını ve Çökme Nedenini İnceleme
kubectl describe pod <pod-name> -n <namespace>

# 2. Çöken (restarted) Konteynerin Bir Önceki Günlüğünü (Log) Sorgulama
kubectl logs <pod-name> -n <namespace> --previous

# 3. Kaynak Kullanımını Denetleme (Eğer metrics-server kuruluysa)
kubectl top pod <pod-name> -n <namespace>
```

### Olası Çözümler

* **OOMKilled Hatası:** Konteyner bellek sınırını aşmıştır. Çözüm için Deployment üzerindeki `limits.memory` değerini artırın:

    ```bash
    kubectl set resources deployment/<deployment-name> -c=<container-name> \
      --limits=memory=1Gi --requests=memory=512Mi -n <namespace>
    ```

* **Hatalı Konfigürasyon:** ConfigMap veya Secret güncellemeleri sonrası pod çökebilir. Secret değerlerini doğrulayın:

    ```bash
    kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}'
    ```

---

## 3. Senaryo 2: Düğüm (Node) NotReady Durumu

Fiziksel veya sanal bir sunucunun `NotReady` durumuna düşmesi durumunda izlenecek kurtarma prosedürü:

```bash
# 1. Düğüm Durumunu Teşhis Etme
kubectl get nodes
kubectl describe node <node-name> | grep -A20 "Conditions:"
kubectl describe node <node-name> | grep -A10 "Events:"
```

### Düğüme Bağlanarak Kurtarma

1. **Düğüme SSH ile Bağlanın:**

    ```bash
    ssh admin@<node-ip>
    ```

2. **Kubelet Servisinin Durumunu Kontrol Edin:**

    ```bash
    systemctl status kubelet
    journalctl -u kubelet -n 50 --no-pager
    ```

3. **Disk Doluluk Oranını İnceleyin (Disk Pressure):**

    ```bash
    df -h
    # Container Runtime cache ve kullanılmayan imajları silerek yer açın
    crictl rmi --prune
    ```

4. **Düğümü Tahliye Edin (Eğer donanımsal arıza varsa veya restart edilecekse):**

    ```bash
    kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
    ```

5. **Düğümü Tekrar Aktif Edin:**

    ```bash
    kubectl uncordon <node-name>
    ```

---

## 4. Senaryo 3: etcd Quorum (Çoğunluk) Kaybı

etcd, tek sayıda düğümle (3 veya 5 master) çalışır. Çoğunluk kaybedildiğinde API Server çalışmaz hale gelir.

### 4.1. Tek Bir etcd Düğüm Arızası (3 düğümden 1'i çöktüğünde)

Sağlıklı düğümlerden birinde çalıştırın:

```bash
# etcdctl ortam değişkenlerini tanımlayın
export ETCD_OPTS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

# 1. Arızalı düğümün üye ID'sini bulun
etcdctl $ETCD_OPTS member list

# 2. Arızalı üyeyi kümeden çıkartın
etcdctl $ETCD_OPTS member remove <failed-member-id>

# 3. Yeni etcd düğümünü ekleyin
etcdctl $ETCD_OPTS member add etcd-node-new --peer-urls=https://<new-node-ip>:2380
```

### 4.2. Tam etcd Çöküşü (Yedekten Geri Yükleme - Restore)

Tüm master düğümlerinde API Server ve etcd manifestlerini geçici olarak kaldırın:

```bash
# 1. Statik manifestleri yedekleme klasörüne taşıyarak servisleri durdurun
mkdir -p /etc/kubernetes/manifests-backup
mv /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/manifests-backup/
mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests-backup/

# 2. Mevcut bozuk veri dizinini yedekleyin
mv /var/lib/etcd /var/lib/etcd-broken

# 3. Yedekten etcd veritabanını geri yükleyin
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --name master-1 \
  --initial-cluster "master-1=https://<master-1-ip>:2380" \
  --initial-advertise-peer-urls https://<master-1-ip>:2380 \
  --data-dir /var/lib/etcd

# 4. Manifest dosyalarını tekrar geri taşıyarak servisleri başlatın
mv /etc/kubernetes/manifests-backup/etcd.yaml /etc/kubernetes/manifests/
mv /etc/kubernetes/manifests-backup/kube-apiserver.yaml /etc/kubernetes/manifests/
```

---

## 5. Senaryo 5: API Server Erişim Sorunları

`kubectl` komutları çalışmadığında veya `connection refused` hatası alındığında:

```bash
# 1. Docker/containerd düzeyinde API Server'ın çalışıp çalışmadığını denetleyin
crictl ps | grep apiserver

# 2. Eğer container çalışmıyorsa loglarını inceleyin
crictl logs <apiserver-container-id>

# 3. Sertifikaların geçerlilik sürelerini kontrol edin
kubeadm certs check-expiration
```

*Çözüm:* Eğer sertifika süreleri dolmuşsa:

```bash
# Sertifikaları yenileyin
kubeadm certs renew all

# Kubelet'i yeniden başlatın
systemctl restart kubelet

# Yeni admin.conf dosyasını kullanıcılara dağıtın
cp /etc/kubernetes/admin.conf ~/.kube/config
```

---

## 6. DR Test ve Tatbikat Takvimi

| Frekans | Yapılacak Test / Tatbikat | Hedef (RTO / RPO) |
| :--- | :--- | :--- |
| **Haftalık** | Velero yedekleme bütünlük kontrolü | RPO: < 24 Saat |
| **Aylık** | Staging üzerinde Velero ile Namespace kurtarma testi | RTO: < 30 Dakika |
| **Çeyreklik (3 Ayda Bir)** | Test kümesinde etcd snapshot restore tatbikatı | RTO: < 2 Saat |
| **Yıllık** | Sıfır altyapıya (Bare-Metal/Cloud) tam küme taşıma (DR) | RTO: < 1 Gün |

> [!CAUTION]
> **UYARI:** etcd snapshot geri yükleme (restore) işlemlerini asla çalışan bir üretim kümesinde denemeyin. Geri yükleme işlemi küme state'ini geçmişe götürür ve veri uyumsuzluklarına yol açabilir. Bu tatbikatları sadece izole test ortamlarında yapın.
