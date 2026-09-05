# Felaket Kurtarma (Disaster Recovery) Runbook

Bu kılavuz, bir Kubernetes kümesinde (cluster) yaşanabilecek kritik ve acil durum senaryolarında, sistem mühendisleri ve SRE / DevOps ekipleri tarafından adım adım izlenmesi gereken felaket kurtarma (Disaster Recovery - DR) prosedürlerini ve acil müdahale akışlarını içerir.

---

## 1. Hazırlık ve Önleyici Kontroller (Pre-DR Checklist)

Kriz anında veri ve hizmet kaybını en aza indirmek için yedekleme ve denetleme adımları düzenli olarak işletilmelidir:

```bash
# 1. etcd Anlık Görüntüsünü (Snapshot) Kaydetme (Günlük/Haftalık)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 2. Velero ile Uygulama ve PV Durum Yedeği Alma
velero backup create weekly-backup-$(date +%Y%m%d) \
  --include-namespaces production,staging \
  --ttl 720h

# 3. Küme TLS Sertifika Sürelerinin Kontrolü
kubeadm certs check-expiration

# 4. etcd Üye Sağlığının Doğrulanması
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --write-out=table \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## 2. Acil Durum Seviyeleri ve Müdahale Akışı (Triage)

Olay anında paniği önlemek için SRE eskalasyon matrisi takip edilir:

| Seviye | Tanım | Örnek Durum | Hedef Müdahale Süresi |
| :--- | :--- | :--- | :--- |
| **P1 (Kritik)** | Küme geneli hizmet kesintisi | etcd çoğunluk kaybı, API Server çökmesi, CoreDNS/CNI kilitlenmesi | < 15 Dakika |
| **P2 (Yüksek)** | Yedeklilik kaybı veya kısmi arıza | Master düğümlerden birinin çökmesi, Storage latency artışı | < 1 Saat |
| **P3 (Orta/Düşük)**| İzole iş yükü hataları | Tek bir Pod'un CrashLoopBackOff olması, bellek aşımı (OOM) | < 4 Saat |

---

## 3. Senaryo 1: Pod CrashLoopBackOff ve OOMKilled Hataları

Bir podun sürekli yeniden başlaması ve trafiğe yanıt verememesi durumunda:

```bash
# 1. Pod Detaylarını ve Çökme Nedenini İnceleme
kubectl describe pod <pod-name> -n <namespace>

# 2. Çöken (restarted) Konteynerin Bir Önceki Günlüğünü (Log) Sorgulama
kubectl logs <pod-name> -n <namespace> --previous

# 3. Kaynak Kullanımını Denetleme (Eğer metrics-server kuruluysa)
kubectl top pod <pod-name> -n <namespace>
```

### Olası Çözümler

* **OOMKilled Hatası (Exit Code 137):** Konteyner bellek sınırını aşmıştır. İlgili Deployment üzerinde `limits.memory` değerini güncelleyin:

    ```bash
    kubectl set resources deployment/<deployment-name> -c=<container-name> \
      --limits=memory=1Gi --requests=memory=512Mi -n <namespace>
    ```

* **Hatalı Konfigürasyon veya Secret Eksikliği:** Secret içeriğini doğrudan deşifre ederek ortam değişkenlerini doğrulayın:

    ```bash
    kubectl get secret <secret-name> -n <namespace> -o json | jq -r '.data | map_values(@base64d)'
    ```

---

## 4. Senaryo 2: Düğüm (Node) NotReady Durumu

Bir fiziksel veya sanal sunucunun `NotReady` durumuna düşmesi durumunda:

```bash
# 1. Düğüm Durumunu ve Olayları Teşhis Etme (Yönetim Makinesinde)
kubectl get nodes
kubectl describe node <node-name> | grep -A20 "Conditions:"
kubectl describe node <node-name> | grep -A10 "Events:"
```

### Adım Adım Kurtarma

1. **Düğüme SSH ile Bağlanın:**
   ```bash
   ssh admin@<node-ip>
   ```

2. **Kubelet ve Container Runtime Durumunu İnceleyin:**
   ```bash
   systemctl status kubelet
   journalctl -u kubelet -n 50 --no-pager
   ```

3. **Disk Baskısını (DiskPressure) Giderin:**
   ```bash
   df -h
   # Kullanılmayan container imajlarını ve önbelleği temizleyin
   crictl rmi --prune
   ```

4. **Yönetim Makinesinden Düğümü Tahliye Edin ve Yeniden Aktif Hale Getirin:**
   ```bash
   # Donanım bakımı veya reboot öncesi iş yüklerini tahliye edin
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

   # Bakım bittikten sonra düğümü tekrar zamanlamaya açın
   kubectl uncordon <node-name>
   ```

---

## 5. Senaryo 3: Kontrol Düzlemi ve API Server Erişim Sorunları

`kubectl` komutları yanıt vermediğinde veya `connection refused` hatası alındığında:

```bash
# 1. Master düğüme bağlanıp API Server container durumunu sorgulayın
crictl ps | grep apiserver

# 2. Eğer container durduysa hata kayıtlarını çekin
APISERVER_ID=$(crictl ps -a | grep kube-apiserver | head -n1 | awk '{print $1}')
crictl logs $APISERVER_ID

# 3. Küme TLS sertifikalarının geçerlilik sürelerini denetleyin
kubeadm certs check-expiration
```

### Sertifika Süresi Dolmuşsa Kurtarma

```bash
# Tüm kontrol düzlemi sertifikalarını yenileyin
kubeadm certs renew all

# Kubelet servisini yeniden başlatarak yeni sertifikaları yükleyin
systemctl restart kubelet

# Yeni admin.conf dosyasını yerel kubeconfig ile güncelleyin
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## 6. Senaryo 4: etcd Quorum (Çoğunluk) Kaybı ve Veritabanı Kurtarma

etcd tek sayıda düğümle (3 veya 5 master) çalışır. Çoğunluk kaybedildiğinde API Server kilitlenir.

### 6.1. Tek Düğüm Arızası (3 Düğümden 1'i Arızalandığında)

Sağlıklı kalan master düğümlerinden birinde:

```bash
export ETCDCTL_API=3
export ETCD_OPTS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

# 1. Arızalı üyenin ID'sini tespit edin
etcdctl $ETCD_OPTS member list

# 2. Arızalı üyeyi kümeden çıkartın
etcdctl $ETCD_OPTS member remove <failed-member-id>

# 3. Yeni master eklendiğinde üye olarak dahil edin
etcdctl $ETCD_OPTS member add etcd-node-new --peer-urls=https://<new-node-ip>:2380
```

### 6.2. Tam Quorum Kaybı (Disaster Recovery Kontrol Listesi)

Tüm master düğümlerinde konsensüs kaybedildiğinde:

1. Tüm master düğümlerindeki `/etc/kubernetes/manifests/` altındaki `etcd.yaml` ve `kube-apiserver.yaml` dosyalarını geçici bir klasöre taşıyarak çöken süreçleri durdurun.
2. Mevcut bozuk veri dizinini (`/var/lib/etcd`) silmeyin; `/var/lib/etcd.corrupted` adıyla yedekleyin.
3. En güncel sağlıklı snapshot dosyasını (`etcdctl snapshot restore`) hayatta kalan tek bir düğüm üzerinde `--initial-cluster` parametresiyle tek düğümlü olarak açın.
4. Tek düğüm ayağa kalkıp sağlıklı çalıştığında, diğer master düğümlerini sıfırdan `member add` ile kümeye dahil edin.

*(Ayrıntılı adım adım komutlar, parametreler ve multi-master senaryoları için bkz: [09. etcd Felaket Kurtarma ve Çekirdek Kaybı Senaryoları](09_etcd_felaket_kurtarma.md)).*

---

## 7. Senaryo 5: Velero ile Uygulama ve Tam Küme Kurtarma (Site Disaster)

Bir veri merkezinin tamamen çökmesi veya kritik bir namespace'in kazara silinmesi durumunda Velero ile nesne ve kalıcı disk (PV) kurtarma adımları:

```bash
# 1. Nesne Depolamadaki (S3/MinIO) Mevcut Yedekleri Listeleyin
velero backup get

# 2. Silinen veya Çöken Namespace'i En Son Yedeğinden Kurtarın
velero restore create restore-prod-$(date +%Y%m%d%H%M) \
  --from-backup weekly-backup-latest \
  --include-namespaces production

# 3. Restorasyon Sürecini ve Ayrıntılarını Denetleyin
velero restore describe restore-prod-latest
velero restore logs restore-prod-latest

# 4. Geri Yüklenen Kaynakların ve Kalıcı Hacimlerin (PV) Sağlığını Doğrulayın
kubectl get pods -n production
kubectl get pvc -n production
```

---

## 8. DR Test ve Tatbikat Takvimi

| Frekans | Yapılacak Test / Tatbikat | Hedef (RTO / RPO) |
| :--- | :--- | :--- |
| **Haftalık** | Velero yedekleme bütünlük kontrolü | RPO: < 24 Saat |
| **Aylık** | Staging üzerinde Velero ile Namespace kurtarma testi | RTO: < 30 Dakika |
| **Çeyreklik (3 Ayda Bir)** | İzole test kümesinde etcd snapshot restore tatbikatı | RTO: < 2 Saat |
| **Yıllık** | Sıfır altyapıya (Bare-Metal/Cloud) tam küme taşıma (DR) | RTO: < 1 Gün |

> [!CAUTION]
> **UYARI:** etcd snapshot geri yükleme (restore) işlemlerini asla çalışan canlı bir üretim kümesinde tatbikat amaçlı denemeyin. Geri yükleme işlemi küme durumunu geriye sarar ve veri uyumsuzluklarına yol açabilir. Bu tatbikatları sadece izole test ortamlarında uygulayın.
