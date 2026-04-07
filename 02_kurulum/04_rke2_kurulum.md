```console
██████╗ ██╗  ██╗███████╗██████╗     ██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ███╗   ██╗███████╗████████╗███████╗███████╗
██╔══██╗██║ ██╔╝██╔════╝╚════██╗    ██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗████╗  ██║██╔════╝╚══██╔══╝██╔════╝██╔════╝
██████╔╝█████╔╝ █████╗   █████╔╝    █████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██╔██╗ ██║█████╗     ██║   █████╗  ███████╗
██╔══██╗██╔═██╗ ██╔══╝  ██╔═══╝     ██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║╚██╗██║██╔══╝     ██║   ██╔══╝  ╚════██║
██║  ██║██║  ██╗███████╗███████╗    ██║  ██╗╚██████╔╝██████╔╝███████╗██║  ██║██║ ╚████║███████╗   ██║   ███████╗███████║
╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚══════╝╚══════╝
               ,        ,
   ,-----------|'------'| 
  /.           '-'    |-'
 |/|             |    |
   |   .________.'----'
   |  ||        |  ||
   \__|'        \__|'  BY SUSE
      ___             _           _                
     |  _|___ ___ _ _| |_ ___ _ _| |___ ___ 
     |  _| .'|  _| | | '_| . | | | | -_|  _|
WWW .|_| |__,|_| |___|_,_|  _|___|_|___|_|.COM

Name: RKE2 (Rancher Kubernetes Engine 2) Cluster Installation Script
POC: Debian 12 "Bookworm"
Author: faruk guler
Date: 2025
Cluster Type: Single / HA-ready
```

# RKE2 — Güvenlik Odaklı Kurulum

RKE2 (Rancher Kubernetes Engine 2), 2026'da kurumsal dünyada bankacılık, savunma ve kamu sektörü için standart hale gelmiş, güvenlik öncelikli Kubernetes dağıtımıdır.

## 4.1 Neden RKE2?

| Özellik | kubeadm | RKE2 |
|:---|:---:|:---:|
| FIPS 140-2 Uyum | âŒ | ✅ |
| CIS Benchmark | Manuel | Otomatik |
| STIG Uyum | âŒ | ✅ |
| Air-gap kurulum | Zor | Kolay |
| Bağımlılık | Çok | Az (bundled) |
| SELinux desteği | Kısmi | Tam |

## 4.2 Minimum Sistem Gereksinimleri

Profesyonel bir RKE2 kurulumu için aşağıdaki minimum değerler (2026 standartları) önerilir:

| Bileşen | CPU | RAM | Disk | Rol |
|:---|:---:|:---:|:---:|:---|
| **Server (Master)** | 4 Core | 8 GB | 100 GB | `server` |
| **Agent (Worker)** | 4 Core | 8 GB | 100 GB | `agent` |

> [!IMPORTANT]
> Hostname'lerin her node'da benzersiz olması ve `/etc/hosts` dosyasında tanımlı olması kritik öneme sahiptir.

## 4.2 Server (Master) Kurulumu

```bash
# Kurulum scripti
curl -sfL https://get.rke2.io | sh -

# Servisi etkinleştir ve başlat
systemctl enable rke2-server.service
systemctl start rke2-server.service

# Kurulum loglarını izle
journalctl -u rke2-server -f
```

## 4.3 RKE2 Yapılandırması

RKE2 yapılandırması `/etc/rancher/rke2/config.yaml` üzerinden yönetilir:

```yaml
# /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"         # 2026 Standardı: Okunabilir kubeconfig
profile: "cis"                        # CIS Benchmark profilini etkinleştir
selinux: true                         # SELinux desteği
cni: "cilium"                         # Cilium CNI seçimi
disable:
  - rke2-ingress-nginx                # Ingress yerine Gateway API kullanacağız
node-label:
  - "environment=production"
  - "compliance=cis"

# --- YÜKSEK ERİŞİLEBİLİRLİK (HA) İÇİN ---
# İlk Master node'da:
cluster-init: true
# tls-san:
#   - my-kubernetes-lb.example.com     # Load Balancer DNS ismi

# Diğer Master node'larda (2. ve 3. master):
# server: https://<ILK_MASTER_IP>:9345
# token: <SERVER_NODE_TOKEN>
```

> [!NOTE]
> `profile: "cis"` değeri, CIS Kubernetes Benchmark testlerinden otomatik olarak geçecek şekilde yapılandırma yapar. Eski versiyonlarda `cis-1.23` şeklinde yazılırdı; 2026 standardında sadece `cis` yeterlidir.

## 4.4 kubeconfig Erişimi

```bash
# RKE2'nin kendi kubectl'i
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes

# Veya sistem kubectl'ini kullanmak için sembolik link
ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
```

## 4.5 Agent (Worker) Node Ekleme

```bash
# 1. Server'dan token al
cat /var/lib/rancher/rke2/server/node-token

# 2. Worker node'da agent kurulumu
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -

# 3. Worker yapılandırmasını oluştur
mkdir -p /etc/rancher/rke2/
cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<SERVER_IP>:9345
token: <YUKARDAKI_TOKEN>
EOF

# 4. Servisi başlat
systemctl enable rke2-agent.service
systemctl start rke2-agent.service
```

## 4.6 Air-Gap (Hava Boşluklu) Kurulum

İnternetsiz ortamlar için:

```bash
# Kapalı sistemde: paketleri önceden indir
curl -OL https://github.com/rancher/rke2/releases/download/v1.32.0+rke2r1/rke2-images.linux-amd64.tar.zst
curl -OL https://github.com/rancher/rke2/releases/download/v1.32.0+rke2r1/rke2.linux-amd64.tar.gz

# Hedef sistemde kur
mkdir -p /var/lib/rancher/rke2/agent/images/
cp rke2-images.linux-amd64.tar.zst /var/lib/rancher/rke2/agent/images/
INSTALL_RKE2_ARTIFACT_PATH=/path/to/downloads sh install.sh
```

## 4.7 CIS Denetimi: kube-bench

RKE2 ile CIS uyumunu doğrulama:

```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-rke2.yaml
kubectl logs job.batch/kube-bench
```

## 4.8 Güvenlik Duvarı (Firewall) Gereksinimleri

RKE2'nin sağlıklı çalışması için aşağıdaki portların açık olması gerekir:

**Control Plane (Server) Node:**
- **TCP 6443**: Kubernetes API Server
- **TCP 9345**: RKE2 Supervisor (Node join için)
- **TCP 2379-2380**: etcd client/peer
- **TCP 10250**: Kubelet API
- **UDP 8472**: VXLAN (Canal/Flannel CNI için)

**Worker (Agent) Node:**
- **TCP 10250**: Kubelet API
- **TCP 30000-32767**: NodePort Servisleri
- **UDP 8472**: VXLAN

## 4.9 Sertifika Yönetimi ve Rotasyon

RKE2 sertifikaları varsayılan olarak 365 gün geçerlidir. Manuel rotasyon için:

```bash
# Sertifikaları yenile
sudo rke2 certificate rotate

# Servisleri her node'da sırayla yeniden başlat
sudo systemctl restart rke2-server  # Server'larda
sudo systemctl restart rke2-agent   # Agent'larda
```

> [!TIP]
> RKE2, özellikle **STIG** (Security Technical Implementation Guide) gereksinimleri olan sektörler için `kubeadm`'a göre çok daha az manuel yapılandırma gerektirir. Bankacılık, savunma ve sağlık sektöründe RKE2 tercih edin.

---

## 4.10 RKE2 Versiyon Yükseltme (Upgrade)

RKE2 cluster'ını yeni bir sürüme yükseltmek için güvenli operasyon akışı:

### 1. Ön Hazırlık (Tavsiye)
- **Snapshot/Backup:** VM düzeyinde snapshot alın.
- **Drenaj:** Node'u servis dışı bırakın: `kubectl drain <node-adı> --ignore-daemonsets --delete-emptydir-data`

### 2. İkili Dosyaları Güncelle (Tüm Node'larda)
```bash
# Otomatik çekirdek güncelleme scripti
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=latest sh -
```

### 3. Servisleri Yeniden Başlat (Sırayla)
Server node'larda (her seferinde biri):
```bash
sudo systemctl restart rke2-server
```

Agent node'larda (her seferinde biri):
```bash
sudo systemctl restart rke2-agent
```

### 4. Node'u Geri Al (Uncordon)
```bash
kubectl uncordon <node-adı>
```

