# Sistem Hazırlığı (Tüm Node'lar)

Bu adımlar, hem Master hem Worker node'larda `root` yetkisiyle çalıştırılmalıdır.

> [!WARNING]
> Bu adımlar atlanırsa `kubelet` başlatılamaz ve cluster kurulumu başarısız olur.

## 1.1 Swap Kapatma

Kubernetes, swap açıkken düzgün çalışmaz:

```bash
# Anlık swap kapatma
swapoff -a

# Kalıcı olarak devre dışı bırakmak için fstab dosyasını düzenleyin
# swap satırının başına # ekleyin veya satırı tamamen silin
vi /etc/fstab

# Doğrulama (çıktı boş olmalı)
free -m
swapon --show

# Sunucu Kimlik Kontrolü (Node Uniqueness)
# Her node'un benzersiz bir UUID'ye sahip olması gerekir
lsb_release -a
sudo cat /sys/class/dmi/id/product_uuid
```

## 1.2 NTP Zaman Senkronizasyonu (Chrony)

Cluster bileşenleri arasındaki sertifika geçerliliği ve log tutarlılığı için zamanın senkron olması kritiktir:

```bash
# Chrony kurulumu
sudo apt install -y chrony

# Servis kontrolü
sudo systemctl enable --now chrony
sudo systemctl start chrony

# Senkronizasyon durumu
chronyc tracking
timedatectl
```

## 1.3 Kernel Modülleri

```bash
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Doğrulama
lsmod | grep -E 'overlay|br_netfilter'
```

## 1.4 Sysctl Ağ Parametreleri

```bash
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Parametreleri anında uygula
sysctl --system

# Doğrulama
sysctl net.ipv4.ip_forward
```

## 1.5 Container Runtime: Containerd Kurulumu

2026 standardı: `containerd` (Kubernetes, Docker'ı CRI olarak artık desteklemiyor)

```bash
# Paket güncelleme ve kurulum
sudo apt-get update && sudo apt-get install -y containerd

# Varsayılan yapılandırma dosyasını oluştur
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# SystemdCgroup'u etkinleştir (ZORUNLU)
# Kubelet ile containerd arasında cgroup driver uyumsuzluğunu önler
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml

# Yapılandırmayı manuel kontrol etmek için (Opsiyonel)
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options] altına bakın
sudo vi /etc/containerd/config.toml

# Servisi yeni yapılandırma ile başlat ve boot sırasında aktif et
sudo systemctl restart containerd
sudo systemctl enable containerd

# Doğrulama
sudo systemctl status containerd
containerd --version
```

> [!NOTE]
> `SystemdCgroup = true` ayarı kritiktir. Aksi takdirde kubelet başlatılamaz ve pod'lar `CrashLoopBackOff` durumuna düşer.

## 1.6 Güvenlik Duvarı (Firewall) Kuralları

Master node için açılması gereken portlar:

```bash
# Master Node portları
ufw allow 6443/tcp    # Kubernetes API Server
ufw allow 2379/tcp    # etcd client
ufw allow 2380/tcp    # etcd peer
ufw allow 10250/tcp   # kubelet API
ufw allow 10257/tcp   # kube-controller-manager
ufw allow 10259/tcp   # kube-scheduler
```

Worker Node için:

```bash
# Worker Node portları
ufw allow 10250/tcp              # kubelet API
ufw allow 30000:32767/tcp        # NodePort Servisleri
```

> [!TIP]
> Eğer tüm node'lar aynı iç ağdaysa ve güvenilir bir ortamdaysa, `ufw disable` ile güvenlik duvarını tamamen kapatabilirsiniz (test ortamı için).

## 1.7 Ek: Önerilen Hostname Yapılandırması

```bash
# Master node'da
hostnamectl set-hostname k8s-master-01

# Worker node'larda
hostnamectl set-hostname k8s-worker-01
hostnamectl set-hostname k8s-worker-02

# /etc/hosts dosyasına tüm node IP'lerini ekle (her node'da)
cat <<EOF >> /etc/hosts
192.168.1.10  k8s-master-01
192.168.1.11  k8s-worker-01
192.168.1.12  k8s-worker-02
EOF
```


