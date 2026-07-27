# Kontrol Düzlemi (Control Plane) Sorun Giderme

Kubernetes Kontrol Düzlemi (Control Plane) bileşenlerinde yaşanacak aksaklıklar en kritik hata senaryolarıdır. API Server çalışmadığında küme yönetilemez, Scheduler durduğunda yeni podlar dağıtılamaz ve etcd bozulduğunda tüm küme durumu (state) kaybolur.

---

## 1. API Server Erişim Sorunları

API Server'a erişim kesildiğinde `kubectl` komutları hata verir. Bu durumda yapılacak ilk kontroller:

```bash
# 1. API Server Sağlık Uç Noktalarını (Endpoints) Sorgulama
curl -k https://<control-plane-ip>:6443/healthz
curl -k https://<control-plane-ip>:6443/readyz

# 2. Bağlantı ve Kubeconfig Detaylarını Denetleme
kubectl cluster-info
kubectl config view --minify
```

### Static Pod Durumlarının Sorgulanması

Control Plane bileşenleri (API Server, Controller Manager, Scheduler ve etcd) master düğümler üzerinde kubelet tarafından yönetilen **Static Pod**'lar olarak çalışır. API Server kapalıyken bile container runtime (CRI) üzerinden bunları inceleyebilirsiniz:

```bash
# Master düğüme SSH yapın ve konteynerleri listeyin
crictl ps | grep -E "apiserver|etcd|scheduler|controller"

# API Server konteyner günlüklerini (logs) çekin
APISERVER_ID=$(crictl ps | grep kube-apiserver | awk '{print $1}')
crictl logs $APISERVER_ID 2>&1 | tail -50

# Yeniden başlaması için static pod manifestini "tetikleyin" (touch)
touch /etc/kubernetes/manifests/kube-apiserver.yaml
```

---

## 2. etcd Sorunları ve Küme Durumu

etcd kümesinin tutarlılığını kaybetmesi veya yavaş çalışması tüm API Server işlemlerini kilitler.

```bash
# etcdctl ortam değişkenlerini ayarlayın
export ETCD_OPTS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

# 1. etcd Küme Sağlığını Kontrol Etme
etcdctl $ETCD_OPTS endpoint health --write-out=table

# 2. etcd Küme Üyelerini ve Liderlik Durumunu Sorgulama
etcdctl $ETCD_OPTS member list --write-out=table
etcdctl $ETCD_OPTS endpoint status --write-out=table

# 3. Disk ve Ağ Performansını Kontrol Etme
etcdctl $ETCD_OPTS check perf

# 4. Veritabanı Fragmantasyonunu Giderme (Compact & Defrag)
etcdctl $ETCD_OPTS defrag
```

> [!WARNING]
> etcd veri dizini (`/var/lib/etcd`) yüksek disk G/Ç (I/O) hızına ihtiyaç duyar. Üretim ortamlarında **SSD/NVMe diskler zorunludur**. Disk gecikmesi (fsync latency) 10ms'yi aşarsa etcd lider seçim süreçleri kilitlenir ve küme kararsızlaşır.

---

## 3. Sertifika Sürelerinin Dolanması

Kubernetes bileşenlerinin kendi aralarında mTLS ile haberleşmesini sağlayan sertifikaların süreleri dolarsa, bileşenler birbirine güvenmeyi bırakır ve küme çöker.

```bash
# 1. Sertifika Geçerlilik Sürelerini Denetleme
kubeadm certs check-expiration

# 2. Tüm Küme Sertifikalarını Yenileme
kubeadm certs renew all

# 3. Kubelet Servisini Yeniden Başlatma
systemctl restart kubelet

# 4. Yenilenen sertifikaların geçerli olması için static pod'ları tetikleyin
for f in /etc/kubernetes/manifests/*.yaml; do touch $f; sleep 5; done

# 5. admin.conf Dosyasını Yerel Kullanıcı Kütüphanesine Kopyalama
cp /etc/kubernetes/admin.conf ~/.kube/config
```

---

## 4. Scheduler ve Controller Manager Sorunları

* Podlar sürekli `Pending` durumunda kalıyor ve düğümlerde yeterli kaynak varsa, sorun **kube-scheduler** bileşenindedir.
* Deployment veya ReplicaSet üzerinde `replicas: 3` yazmasına rağmen fiili pod sayısı değişmiyorsa, sorun **kube-controller-manager** bileşenindedir.

```bash
# 1. Scheduler Loglarını Kontrol Etme
crictl logs $(crictl ps | grep kube-scheduler | awk '{print $1}') 2>&1 | tail -30

# 2. Controller Manager Loglarını Kontrol Etme
crictl logs $(crictl ps | grep controller-manager | awk '{print $1}') 2>&1 | tail -30

# 3. Leader Election (Liderlik) Durumunu İnceleme
# HA mimaride hangi Master'ın aktif çalıştığını gösterir
kubectl get leases -n kube-system | grep -E "scheduler|controller"
```

---

## 5. Teşhis Akış Şeması

```
[ kubectl Çalışmıyor / API Server Bağlantısı Koptu ]
        │
        ├──► 1. API Server Portunu Sorgula (healthz) ──► Yanıt Yoksa?
        │         ├──► SSH Master Node ──► 'crictl ps' ile konteynerleri denetle
        │         └──► Kubelet loglarını oku: 'journalctl -u kubelet -n 50'
        │
        ├──► 2. etcd Sağlığını Denetle (etcdctl) ──► Sağlıksızsa?
        │         └──► Disk gecikmesini / disk doluluğunu kontrol et (df -h)
        │
        └──► 3. Sertifika Sürelerini Sorgula (check-expiration) ──► Süre Dolmuşsa?
                  └──► 'kubeadm certs renew all' ile yenile
```
