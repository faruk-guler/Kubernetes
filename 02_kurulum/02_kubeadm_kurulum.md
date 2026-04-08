```console
      __  __           __                                            __                       
     /\ \/\ \         /\ \                                          /\ \__                 
     \ \ \/'/'  __  __\ \ \____     __   _ __    ___      __    ____\ \ ,_\    __    ____  
      \ \ , <  /\ \/\ \\ \ '__`\  /'__`\/\`'__\/' _ `\  /'__`\ /',__\\ \ \/  /'__`\ /',__\ 
       \ \ \\`\\ \ \_\ \\ \ \L\ \/\  __/\ \ \/ /\ \/\ \/\  __//\__, `\\ \ \_/\  __//\__, `\
        \ \_\ \_\ \____/ \ \_,__/\ \____\\ \_\ \ \_\ \_\ \____\/\____/ \ \__\ \____\/\____/
         \/_/\/_/\/___/   \/___/  \/____/ \/_/  \/_/\/_/\/____/\/___/   \/__/\/____/\/___/
      ___             _           _                         
     |  _|___ ___ _ _| |_ ___ _ _| |___ ___  
     |  _| .'|  _| | | '_| . | | | | -_|  _|
WWW .|_| |__,|_| |___|_,_|  _|___|_|___|_|.COM

Name: (Vanilla) Kubernetes Cluster Installation Script
POC: Debian 12 "Bookworm"
Author: faruk guler
Date: 2026
```

# kubeadm ile Cluster Kurulumu

> [!IMPORTANT]
> Bu adımları uygulamadan önce Sistem Hazırlığı bölümündeki tüm adımları tamamladığınızdan emin olun.

## 2.1 kubeadm, kubelet ve kubectl Kurulumu (Tüm Node'lar)

```bash
# Gerekli paketler
apt-get update && apt-get install -y apt-transport-https ca-certificates curl gpg

# Kubernetes paket deposu anahtarı (v1.32)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Depoyu ekle
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list

# Mevcut sürümleri incelemek için (Versiyon Pinning)
apt-cache policy kubelet | head -n 20

# Kurulum (Belirli bir sürüm yüklemek için: kubelet=1.32.1-1.1)
VERSION=1.32.1-1.1
apt-get update && apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION

# Sürümleri kilitle (otomatik güncellemeyi önle)
apt-mark hold kubelet kubeadm kubectl containerd

# Kubelet ve Containerd servislerini etkinleştir (Boot ayarı)
systemctl enable --now kubelet
systemctl enable --now containerd

# Doğrulama (Kubelet fail edebilir, init sonrası düzelecektir)
systemctl status kubelet.service
```

## 2.2 Control Plane Başlatma (Yalnızca Master Node)

2026 standardında `kube-proxy` **devre dışı** bırakılarak Cilium'un tüm ağ yönetimi üstlenmesi sağlanır:

```bash
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --skip-phases=addon/kube-proxy \
  --kubernetes-version=v1.32.0
```

> [!IMPORTANT]
> **Ağ Çakışma Kontrolü:** `--pod-network-cidr` (Örn: 10.244.0.0/16) aralığı, sunucularınızın bulunduğu fiziksel yerel ağ (LAN) ile **asla çakışmamalıdır**. Eğer yerel ağınız da 10.x.x.x bloğundaysa, pod ağını 192.168.x.x olarak değiştirin.
>
> **kube-proxy Skip:** `--skip-phases=addon/kube-proxy` parametresi Cilium-eBPF standardı için zorunludur.

### 1. Kubeconfig Ayarı ve Yetkilendirme
```bash
# Yönetici erişimini yapılandır (Root olmayan kullanıcı için de geçerli)
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 2. Statik Pod Manifestlerini İnceleme (Black Belt)
Cluster bileşenleri `kubelet` tarafından statik pod olarak yönetilir:
```bash
# Manifest dosyalarının listesi
ls /etc/kubernetes/manifests

# API Server ve etcd yapılandırmasını kontrol edin
sudo more /etc/kubernetes/manifests/kube-apiserver.yaml
sudo more /etc/kubernetes/manifests/etcd.yaml

# Cluster durumunu genel inceleyin
ls /etc/kubernetes
```

### 3. Pod Network (CNI) Kurulumu ve Takip
CNI kurulmadan önce CoreDNS podları `Pending` durumunda bekler.
```bash
# Detaylı takibi başlat (yeni bir terminalde)
kubectl get pods --all-namespaces --watch

# Cilium veya Calico (Bkz: Sonraki Bölüm) kurulunca Running olacaktır.
```

### Join Token Alma

```bash
# Token listele (Tokenlar 24 saat geçerlidir)
kubeadm token list

# Yeni join komutu üret
kubeadm token create --print-join-command
```

> [!TIP]
> **Black Belt Tip: Manuel CA Hash Hesaplama**
> Eğer join komutu çıktısına erişemiyorsanız, CA sertifikasının hash değerini aşağıdaki manuel yöntemle bulabilirsiniz:
> ```bash
> openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
> ```

## 2.3 Worker Node'ları Ekleme

Her worker node üzerinde, master'dan aldığınız join komutunu çalıştırın:

```bash
# Örnek format (master'dan alınan gerçek değerlerle değiştirin):
kubeadm join <MASTER_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Master node'dan doğrulama:

```bash
kubectl get nodes
# Worker'lar "NotReady" görünür — Cilium kurulana kadar bu normaldir
```

## 2.4 High Availability (HA) Control Plane

Üretim ortamında en az **3 Master Node** önerilir:

```bash
# İlk master'ı kurarken
kubeadm init \
  --control-plane-endpoint="<LOAD_BALANCER_IP>:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16 \
  --skip-phases=addon/kube-proxy

# Çıktıdaki --control-plane bayrağıyla ek master'ları ekle:
kubeadm join <LOAD_BALANCER_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>
```

> [!TIP]
> HA kurulumda master node'ların önüne bir yük dengeleyici (HAProxy veya cloud load balancer) koyun. `--control-plane-endpoint` bu yük dengeleyicinin IP/DNS'ini göstermelidir.

## 2.5 etcd Yedekleme

```bash
# etcd snapshot al
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key

# Snapshot doğrulama
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db
```

> [!CAUTION]
> etcd yedeğini düzenli ve güvenli bir konumda saklayın. etcd olmadan cluster kurtarılamaz.

---

## 2.6 Cluster Upgrade (Versiyon Yükseltme)

Kubernetes cluster'ını bir üst sürüme (Örn: v1.31 -> v1.32) yükseltmek için kullanılan güvenli akış:

### 1. Master Node Yükseltme
```bash
# kubeadm paketini güncelle (Master üzerinde)
apt-get unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.32.1-1.1 && apt-mark hold kubeadm

# Yükseltme planını kontrol et
kubeadm upgrade plan

# Yükseltmeyi başlat
kubeadm upgrade apply v1.32.1

# Kubelet ve Kubectl'i güncelle
apt-get unhold kubelet kubectl && apt-get install -y kubelet=1.32.1-1.1 kubectl=1.32.1-1.1 && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
```

### 2. Worker Node Yükseltme (Sırayla)
```bash
# Master üzerinde node'u boşalt
kubectl drain <worker-node> --ignore-daemonsets

# Worker üzerinde paketleri güncelle
apt-get unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.32.1-1.1 && apt-mark hold kubeadm
kubeadm upgrade node

# Kubelet'i güncelle ve yeniden başlat
apt-get unhold kubelet kubectl && apt-get install -y kubelet=1.32.1-1.1 kubectl=1.32.1-1.1 && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet

# Master üzerinde node'u tekrar aktif et
kubectl uncordon <worker-node>
```

---

## 2.7 Sertifika Yönetimi (Certificate Renewal)

Kubernetes sertifikaları varsayılan olarak **1 yıl** geçerlidir.

```bash
# Sertifika geçerlilik sürelerini kontrol et
kubeadm certs check-expiration

# Tüm sertifikaları manuel yenile
kubeadm certs renew all

# Kubeconfig dosyasını güncelle (Yenileme sonrası zorunludur)
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
```

> [!TIP]
> **Otomatik Yenileme:** Her `kubeadm upgrade` işleminde sertifikalar otomatik olarak 1 yıl daha uzatılır. Düzenli cluster güncellemeleri sertifika sorunlarını önler.

