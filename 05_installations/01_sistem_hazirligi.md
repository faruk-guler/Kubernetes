# Sistem Hazırlığı (System Preparation)

Kubernetes kurulumuna başlamadan önce, kümedeki (cluster) hem Master hem de Worker düğümlerinin (nodes) işletim sistemi seviyesinde belirli ön gereksinimleri karşılaması gerekir.

Bu hazırlık adımları, tüm düğümlerde `root` yetkisiyle (veya `sudo` ile) çalıştırılmalıdır.

> [!WARNING]
> Bu adımların atlanması veya hatalı yapılandırılması durumunda `kubelet` ajanı başlatılamaz ve Kubernetes küme kurulumu başarısız olur.

---

## 1. Swap (Sanal Bellek) Kapatılması

Kubernetes scheduler'ı, podların kaynak limitlerini hassas bir şekilde planlayabilmek için belleği doğrudan takip etmek ister. Swap alanı açık olduğunda bellek hesaplaması tutarsızlaşacağından, Kubernetes swap kullanımını desteklemez ve swap açıkken kubelet servisi başlamayı reddeder.

```bash
# 1. Anlık olarak swap alanını kapatın
swapoff -a

# 2. Kalıcı olarak devre dışı bırakmak için fstab dosyasını düzenleyin
# İçerisinde 'swap' geçen satırın başına '#' ekleyerek yorum satırı yapın veya silin
vi /etc/fstab

# 3. Kapatıldığını doğrulayın (swapon çıktısı boş olmalı, free bellek tablosunda swap 0 görünmelidir)
free -m
swapon --show
```

---

## 2. Sunucu Benzersizlik Kontrolleri

Kubernetes'in düğümleri birbirinden ayırt edebilmesi için her sunucunun benzersiz (unique) ürün UUID'sine ve MAC adresine sahip olması gerekir:

```bash
# Ürün UUID'sini kontrol edin (Her sunucuda farklı olmalıdır)
sudo cat /sys/class/dmi/id/product_uuid

# Ağ arayüzlerinin MAC adreslerini doğrulayın
ip link
```

---

## 3. NTP (Zaman Senkronizasyonu) Yapılandırması

Küme içindeki düğümlerin zamanları arasında fark olması durumunda, TLS sertifikalarının geçerlilik doğrulaması başarısız olur ve log akışlarında tutarsızlıklar yaşanır. Zamanı senkron tutmak için **Chrony** servisi kurulmalıdır:

```bash
# Chrony kurulumu (Ubuntu/Debian)
sudo apt update && sudo apt install -y chrony

# Servisi etkinleştirin ve başlatın
sudo systemctl enable --now chrony
sudo systemctl start chrony

# Senkronizasyon durumunu doğrulayın
chronyc tracking
timedatectl
```

---

## 4. Kernel (Çekirdek) Modüllerinin Yüklenmesi

Kubernetes ağının (CNI) podlar arasında köprü trafiğini (bridge) ve overlay ağ yapılandırmasını düzgün yönetebilmesi için `overlay` ve `br_netfilter` çekirdek modüllerinin yüklenmesi gerekir:

```bash
# Modüllerin her başlangıçta otomatik yüklenmesi için dosya oluşturun
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Modülleri anlık olarak yükleyin
sudo modprobe overlay
sudo modprobe br_netfilter

# Yüklendiğini doğrulayın
lsmod | grep -E 'overlay|br_netfilter'
```

---

## 5. Sysctl Ağ Parametrelerinin Yapılandırılması

Linux çekirdeğinin ağ paketlerini köprüler (bridges) üzerinden doğru geçirebilmesi için IP yönlendirmenin (`ip_forward`) aktif edilmesi zorunludur:

```bash
# Ağ parametrelerini k8s.conf dosyasına yazın
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Parametreleri sisteme anında uygulayın
sudo sysctl --system

# Doğrulayın (Sonuç '1' dönmelidir)
sysctl net.ipv4.ip_forward
```

---

## 6. Container Runtime: containerd Kurulumu

Kubernetes, v1.24 sürümüyle birlikte Docker runtime desteğini (Dockershim) tamamen kaldırmıştır. 2026 yılı standartlarında varsayılan konteyner çalışma zamanı **containerd**'dir.

```bash
# 1. containerd paketini yükleyin
sudo apt-get update && sudo apt-get install -y containerd

# 2. Varsayılan yapılandırma şablonunu oluşturun
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# 3. SystemdCgroup ayarını 'true' yapın (En Kritik Adım!)
# Kubelet ile containerd'nin aynı cgroup sürücüsünü (systemd) kullanmasını sağlar
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml

# 4. Servisi yeni yapılandırma ile yeniden başlatın
sudo systemctl restart containerd
sudo systemctl enable containerd

# 5. Çalışma durumunu doğrulayın
sudo systemctl status containerd
containerd --version
```

---

## 7. Güvenlik Duvarı (Firewall) Kurallarının Ayarlanması

Düğümlerin birbirleriyle ve master düğümle sorunsuz konuşabilmesi için güvenlik duvarında (UFW) gerekli portların açık olması gerekir.

### Master (Control Plane) Düğümleri İçin

```bash
sudo ufw allow 6443/tcp    # Kubernetes API Server (Tüm düğümler erişebilmeli)
sudo ufw allow 2379:2380/tcp # etcd Client ve Peer İletişimi
sudo ufw allow 10250/tcp   # Kubelet API
sudo ufw allow 10257/tcp   # Kube-Controller-Manager
sudo ufw allow 10259/tcp   # Kube-Scheduler
```

### Worker Düğümleri İçin

```bash
sudo ufw allow 10250/tcp       # Kubelet API
sudo ufw allow 30000:32767/tcp # Dışarıya NodePort ile açılan uygulama servisleri
```

*Not: Eğer düğümleriniz güvenli, izole bir iç ağda (LAN/VPC) bulunuyorsa, kurulum aşamasında sorun yaşamamak için `sudo ufw disable` ile güvenlik duvarını tamamen kapatmayı da tercih edebilirsiniz.*

---

## 8. Hostname (Sunucu Adı) Yapılandırması

Kubernetes düğümlerinin ağda birbirlerini çözümleyebilmeleri için anlaşılır hostname'lere sahip olmaları ve `/etc/hosts` dosyalarının güncellenmesi önerilir:

```bash
# Master sunucusunda
hostnamectl set-hostname k8s-master-01

# Worker-1 sunucusunda
hostnamectl set-hostname k8s-worker-01

# Her sunucunun /etc/hosts dosyasına diğer düğümleri ekleyin
cat <<EOF | sudo tee -a /etc/hosts
192.168.10.10  k8s-master-01
192.168.10.11  k8s-worker-01
192.168.10.12  k8s-worker-02
EOF
```

---

## Özet

Bu aşamada swap alanını kapattık, ağ yönlendirme modüllerini (`br_netfilter`, `ip_forward`) yapılandırdık ve **containerd** çalışma zamanını `SystemdCgroup = true` ayarıyla kurduk. Bu hazırlıkların ardından sunucularımız, Kubernetes kurulum araçlarıyla (kubeadm, kubespray vb.) küme inşası yapmaya tamamen hazırdır.
