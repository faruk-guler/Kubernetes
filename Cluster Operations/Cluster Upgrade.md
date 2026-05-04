# Kubernetes Cluster Upgrade

Cluster upgrade, yanlış yapıldığında tüm production'ı durdurabilir. Doğru sıra ve hazırlık hayat kurtarır.

---

## Upgrade Stratejisi

```
Kural 1: Control Plane önce, Worker Node'lar sonra
Kural 2: Bir minor versiyon atla — v1.29 → v1.31 değil, v1.29 → v1.30 → v1.31
Kural 3: etcd'yi upgrade'den ÖNCE yedekle
Kural 4: Her node'u upgrade'den önce drain et
Kural 5: Upgrade'i önce staging'de test et
```

---

## Ön Kontroller

```bash
# Mevcut sürümleri kontrol et
kubectl version
kubectl get nodes -o wide
kubeadm version

# Kullanılabilir sürümleri listele
apt-cache madison kubeadm | head -10   # Debian/Ubuntu
dnf list --available kubeadm | head -10  # RHEL/Fedora

# API deprecation kontrolü
pluto detect-helm --target-versions k8s=v1.31
kubectl deprecations --version=1.31  # kubectl-deprecations plugin

# etcd yedeği al
ETCDCTL_API=3 etcdctl snapshot save /backup/pre-upgrade-etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Yedek doğrula
ETCDCTL_API=3 etcdctl snapshot status /backup/pre-upgrade-etcd.db --write-out=table
```

---

## Control Plane Upgrade (kubeadm)

```bash
# 1. kubeadm güncelle
sudo apt-get update
sudo apt-get install -y kubeadm=1.31.0-1.1
sudo apt-mark hold kubeadm

# 2. Upgrade planını incele
sudo kubeadm upgrade plan v1.31.0
# Çıktı: hangi bileşenler güncelleniyor, API değişiklikleri

# 3. Upgrade uygula
sudo kubeadm upgrade apply v1.31.0 --yes
# Güncelleniyor: API Server, Scheduler, Controller Manager, kube-proxy, CoreDNS

# 4. kubelet ve kubectl güncelle
sudo apt-get install -y kubelet=1.31.0-1.1 kubectl=1.31.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. Kontrol et
kubectl get nodes           # Control plane "Ready" ama version eski gösterebilir
kubectl version             # API Server v1.31 olmalı
```

---

## Worker Node Upgrade

Her node için sırayla uygula — hepsini aynı anda upgrade etme:

```bash
# Control Plane'den — node'u boşalt
kubectl cordon <node-name>
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=60

# Worker Node üzerinde SSH ile bağlan
ssh <node>

# kubeadm upgrade
sudo apt-get update
sudo apt-get install -y kubeadm=1.31.0-1.1
sudo kubeadm upgrade node   # Worker node için bu komut

# kubelet güncelle
sudo apt-get install -y kubelet=1.31.0-1.1 kubectl=1.31.0-1.1
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Control Plane'den — node'u geri al
kubectl uncordon <node-name>

# Node sağlığını kontrol et
kubectl get node <node-name>
kubectl describe node <node-name> | grep -A5 Conditions

# Bir sonraki node'a geç (mevcut node'un pod'ları yerleşene kadar bekle)
kubectl get pods -A -o wide | grep <node-name>
```

---

## Çok Node'lu Control Plane (HA) Upgrade

```bash
# HA cluster'da control plane node'ları tek tek upgrade et
# Her seferinde sadece 1 node → etcd quorum bozulmasın

# Node 1 (primary)
sudo kubeadm upgrade apply v1.31.0

# Node 2
sudo kubeadm upgrade node   # apply değil, node komutu

# Node 3
sudo kubeadm upgrade node

# Tüm control plane node'larında kubelet güncelle
sudo apt-get install -y kubelet=1.31.0-1.1
sudo systemctl daemon-reload && sudo systemctl restart kubelet
```

---

## Managed Kubernetes Upgrade (EKS/GKE/AKS)

```bash
# EKS
aws eks update-cluster-version \
  --name my-cluster \
  --kubernetes-version 1.31

# Node group upgrade
aws eks update-nodegroup-version \
  --cluster-name my-cluster \
  --nodegroup-name workers \
  --kubernetes-version 1.31

# GKE
gcloud container clusters upgrade my-cluster \
  --master \
  --cluster-version 1.31

gcloud container clusters upgrade my-cluster \
  --node-pool default-pool

# AKS
az aks upgrade \
  --resource-group myRG \
  --name my-cluster \
  --kubernetes-version 1.31.0 \
  --yes
```

---

## Upgrade Sonrası Doğrulama

```bash
# Tüm node'lar yeni versiyonda mı?
kubectl get nodes -o custom-columns=\
  NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,STATUS:.status.conditions[-1].type

# Kritik pod'lar çalışıyor mu?
kubectl get pods -n kube-system
kubectl get pods -A --field-selector=status.phase!=Running

# API server sağlık kontrolü
kubectl get --raw /healthz
kubectl get --raw /readyz

# etcd sağlık
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Uygulama pod'ları çalışıyor mu?
kubectl get pods -A | grep -v Running | grep -v Completed
```

---

## Geri Alma (Rollback)

```bash
# etcd snapshot'tan geri dön (son çare)
# Control plane'i durdur
sudo systemctl stop kubelet

# etcd verisini temizle ve snapshot'ı yükle
ETCDCTL_API=3 etcdctl snapshot restore /backup/pre-upgrade-etcd.db \
  --data-dir=/var/lib/etcd-restore \
  --initial-cluster=master=https://127.0.0.1:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://127.0.0.1:2380

# Eski veriyi yedekle, restore'u aktif et
sudo mv /var/lib/etcd /var/lib/etcd-old
sudo mv /var/lib/etcd-restore /var/lib/etcd

# kubelet yeniden başlat
sudo systemctl start kubelet
```

> [!IMPORTANT]
> Upgrade öncesi `kubectl get all -A -o yaml > full-backup.yaml` ile tüm kaynakları yedekleyin. etcd snapshot + manifest yedeği = çift güvence.

> [!WARNING]
> `kubeadm upgrade apply` sonrası kubelet güncellenmezse node eski versiyonda görünür ama API Server yeni versiyonda çalışır — `kubectl get nodes` çıktısında versiyon uyuşmazlığı bu yüzden olur. Her zaman kubelet'i de güncelle.
