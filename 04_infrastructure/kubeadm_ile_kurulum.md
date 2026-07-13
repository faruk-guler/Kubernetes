# kubeadm ile Cluster Kurulumu (Vanilla Kubernetes Cluster)

**kubeadm**, Kubernetes topluluğu (SIG Cluster Lifecycle) tarafından geliştirilen ve standartlara tam uyumlu (Vanilla) bir Kubernetes kümesi kurmak, güncellemek ve yönetmek için kullanılan resmi ve birincil araçtır.

Bu bölümde, Debian/Ubuntu tabanlı sistemler üzerinde sıfırdan çok düğümlü ve yüksek kullanılabilirliğe (HA) sahip bir Kubernetes kümesinin `kubeadm` kullanılarak nasıl kurulacağını adım adım inceleyeceğiz.

> [!IMPORTANT]
> Bu adımlara geçmeden önce, tüm düğümlerde **Sistem Hazırlığı** (Swap kapatma, kernel modülleri, sysctl ağ yapılandırmaları ve containerd kurulumu) bölümündeki adımların eksiksiz tamamlandığından emin olun.

---

## 1. kubeadm, kubelet ve kubectl Kurulumu (Tüm Düğümlerde)

Kubernetes paketlerini yüklemek için resmi topluluk depoları sisteme eklenmelidir:

```bash
# 1. Gerekli ön paketleri yükleyin
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 2. Kubernetes paket deposu imzalama anahtarını (v1.32) indirin
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 3. Kubernetes deposunu kaynak listenize ekleyin
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 4. Paket listesini güncelleyip paket sürümlerini kontrol edin (Version Pinning)
sudo apt-get update
apt-cache policy kubelet | head -n 15

# 5. Belirli bir sürüm belirterek kurulumu yapın (Örn: v1.32.1)
VERSION=1.32.1-1.1
sudo apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION

# 6. Sürümleri kilitleyin (apt upgrade sırasında otomatik güncellenmelerini önler)
sudo apt-mark hold kubelet kubeadm kubectl

# 7. Kubelet servisini sistem başlangıcına ekleyin ve çalıştırın
sudo systemctl enable --now kubelet
```

---

## 2. Control Plane (Master Düğümü) Başlatılması

Kurulumu başlatırken, 2026 yılı modern mimari standartlarına uygun olarak `kube-proxy` bileşenini kurmayıp, tüm ağ yönetimini eBPF tabanlı **Cilium**'a devredeceğiz. Bu sayede `skip-phases` parametresini kullanacağız.

Master sunucu üzerinde aşağıdaki komutu çalıştırarak küme kurulumunu başlatın:

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --skip-phases=addon/kube-proxy \
  --kubernetes-version=v1.32.1
```

> [!IMPORTANT]
> **Ağ Çakışma Kontrolü:** `--pod-network-cidr` (Örn: 10.244.0.0/16) aralığı, sunucularınızın kurulu olduğu fiziksel yerel ağ (VPC/LAN) IP aralığı ile **çakışmamalıdır**. Eğer yerel ağınız 10.x.x.x bloğundaysa, pod ağını `192.168.0.0/16` olarak değiştirmelisiniz.

Kurulum başarıyla tamamlandığında ekrana bir **join token** ve kubeconfig ayar komutları gelecektir.

---

## 3. Yönetici Erişimi (Kubeconfig) Ayarı

Kümenizi `kubectl` ile yönetebilmek için, master düğümü üzerinde yönetici yetkilendirme dosyasını kopyalayın:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Artık ilk durum kontrollerini yapabilirsiniz:

```bash
kubectl get nodes
# Çıktıda master node "NotReady" görünecektir. Bu durum, bir CNI ağ plugin'i
# (Cilium vb.) kurulana kadar normaldir; CoreDNS podları da bu aşamada Pending bekler.
```

---

## 4. Statik Pod Yapısını İnceleme

Kubeadm ile kurulan çekirdek Kubernetes bileşenleri, işletim sistemi servisi olarak değil, `/etc/kubernetes/manifests` dizini altındaki YAML tanımlarına göre doğrudan **kubelet** tarafından birer **Statik Pod (Static Pod)** olarak yönetilir:

```bash
# Manifest dosyalarını listeleme
ls /etc/kubernetes/manifests
# Çıktı: etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

# API Server konfigürasyonunu inceleme
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

---

## 5. Worker Düğümlerinin Kümeye Dahil Edilmesi (Join)

Yeni bir worker düğümünü kümeye bağlamak için Master düğümü üzerinde üretilen join komutunu her worker düğümü üzerinde `root` yetkisiyle çalıştırın:

```bash
sudo kubeadm join 192.168.10.10:6443 \
  --token abcdef.1234567890abcdef \
  --discovery-token-ca-cert-hash sha256:7f3b8a1c9d2e4f5a...
```

### Token Kaybolduysa veya Süresi Dolduysa (24 Saat Sonra)

Yeni bir katılım komutu üretmek için master düğümünde şu komut çalıştırılır:

```bash
kubeadm token create --print-join-command
```

---

## 6. Yüksek Kullanılabilirlik (High Availability - HA) Yapısı

Üretim ortamlarında Control Plane yedekliliği sağlamak amacıyla en az **3 Master Düğümü** kurulması önerilir. Bu düğümlerin önüne bir Load Balancer (Örn: HAProxy veya AWS NLB) konumlandırılmalı ve API istekleri bu yük dengeleyici üzerinden dağıtılmalıdır.

### İlk Master Düğümün Kurulumu

```bash
sudo kubeadm init \
  --control-plane-endpoint="<LOAD_BALANCER_IP>:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16 \
  --skip-phases=addon/kube-proxy
```

### Diğer Master Düğümlerini Dahil Etme

Kurulum çıktısındaki `--control-plane` ve `--certificate-key` parametrelerini barındıran join komutunu diğer iki master sunucu üzerinde çalıştırın:

```bash
sudo kubeadm join <LOAD_BALANCER_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERTIFICATE_KEY_DEGERI>
```

---

## 7. Sertifika Sürelerinin Yönetimi ve Yenileme

kubeadm tarafından oluşturulan iç iletişim TLS sertifikalarının geçerlilik süresi varsayılan olarak **1 yıldır**.

```bash
# 1. Sertifikaların geçerlilik sürelerini kontrol edin
kubeadm certs check-expiration

# 2. Tüm sertifikaları manuel olarak 1 yıl daha uzatın
sudo kubeadm certs renew all

# 3. Yenileme sonrası admin kubeconfig dosyasını güncelleyin
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

> [!TIP]
> **Otomatik Yenileme:** Yapacağınız her `kubeadm upgrade` (versiyon yükseltme) işlemi sırasında tüm küme sertifikaları otomatik olarak 1 yıl daha uzatılır. Düzenli güncelleme yapılan kümelerde sertifika süresi sorunu yaşanmaz.

---

## Özet

`kubeadm` aracı, sıfırdan production-ready Kubernetes kümeleri oluşturmak için standart ve en güvenli yöntemdir. eBPF tabanlı CNI geçişleri için `kube-proxy`'yi kurulum aşamasında atlamak (`skip-phases`), sürüm kilitleme (`apt-mark hold`) ve düzenli sertifika takibi, küme kararlılığını sağlamanın temel adımlarıdır.
