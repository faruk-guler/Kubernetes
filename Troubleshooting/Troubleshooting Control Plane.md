# Troubleshooting: Control Plane

Control Plane sorunları en kritik senaryolardır — API Server cevap vermediğinde `kubectl` çalışmaz, Scheduler durduğunda yeni pod'lar çalışmaz, etcd bozulduğunda cluster hafızasını kaybeder.

---

## API Server Erişim Sorunu

```bash
# Sağlık kontrolü
curl -k https://<control-plane-ip>:6443/healthz
curl -k https://<control-plane-ip>:6443/readyz

# kubectl bağlantı detayı
kubectl cluster-info
kubectl config view --minify
```

### Static Pod Olarak Çalışan Bileşenler

Control Plane bileşenleri API Server üzerinden değil, kubelet tarafından doğrudan yönetilir.

```bash
# Control plane node'una SSH
ssh <master-node>

# Static Pod manifestleri
ls /etc/kubernetes/manifests/
# kube-apiserver.yaml / kube-controller-manager.yaml / kube-scheduler.yaml / etcd.yaml

# API Server olmadan container durumu
crictl ps | grep -E "apiserver|etcd|scheduler|controller"
APISERVER_ID=$(crictl ps | grep kube-apiserver | awk '{print $1}')
crictl logs $APISERVER_ID 2>&1 | tail -50

# Yeniden başlatmak için manifesti touch'la
touch /etc/kubernetes/manifests/kube-apiserver.yaml
```

### Yaygın API Server Hataları

```bash
# Sertifika süresi dolmuş → "x509: certificate has expired"
kubeadm certs check-expiration
kubeadm certs renew all

# etcd bağlantısı yok → "context deadline exceeded"
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table
```

---

## etcd Sorunları

```bash
# Sağlık kontrolü
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --write-out=table

# Leader durumu (HA cluster)
etcdctl endpoint status --write-out=table
etcdctl member list --write-out=table

# Disk performansı (yavaşlık tespiti)
etcdctl check perf

# Veritabanı şişmesi — compaction
etcdctl defrag
```

> [!WARNING]
> etcd için **SSD disk zorunludur**. Yüksek fsync gecikmesi leader kaybına yol açar. `/var/lib/etcd` ayrı bir partition olmalı.

---

## Sertifika Sorunları

```bash
# Tüm sertifikaların bitiş tarihi
kubeadm certs check-expiration

# Tümünü yenile
kubeadm certs renew all

# Static pod'ları yeniden başlat
for f in /etc/kubernetes/manifests/*.yaml; do touch $f; sleep 5; done

# Kubeconfig güncelle
cp /etc/kubernetes/admin.conf ~/.kube/config
```

> [!IMPORTANT]
> Sertifika yenileme işlemini yıllık planlı bakım olarak yapın. Varsayılan süre **1 yıl**dır.

---

## Scheduler & Controller Manager

```bash
# Scheduler çalışıyor mu? (Pod'lar Pending ama resource yeterli)
crictl ps | grep kube-scheduler
crictl logs $(crictl ps | grep kube-scheduler | awk '{print $1}') 2>&1 | tail -30

# Leader election durumu
kubectl get leases -n kube-system | grep -E "scheduler|controller"

# Controller Manager (ReplicaSet beklenen sayıya ulaşmıyorsa)
crictl logs $(crictl ps | grep controller-manager | awk '{print $1}') 2>&1 | tail -30
```

---

## Control Plane Tanı Akışı

```
kubectl çalışmıyor
     │
     ├── curl https://<cp>:6443/healthz → Hayır?
     │     SSH → crictl ps | grep apiserver
     │         → Sertifika / etcd / config hatası?
     │
     ├── etcd sağlıklı mı?
     │     etcdctl endpoint health
     │     → Leader yok → ağ/disk sorunu
     │
     ├── Pod'lar Pending (resource var ama schedule olmuyor)?
     │     → Scheduler logları
     │
     └── ReplicaSet beklenen sayıya ulaşmadı?
           → Controller Manager logları
```
