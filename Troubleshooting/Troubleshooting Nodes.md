# Troubleshooting: Nodes

Node sorunları tüm üzerindeki pod'ları etkiler. Bir node çöktüğünde Kubernetes pod'ları başka node'lara taşır — ama bunu yapabilmesi için önce neyin bozulduğunu anlamak gerekir.

---

## Node Durumunu Okumak

```bash
# Tüm node'ların genel durumu
kubectl get nodes
kubectl get nodes -o wide    # IP ve OS bilgisi dahil

# Belirli node'un detayı
kubectl describe node <node-adı>
```

`describe` çıktısında dikkat edin:
- **Conditions** — Ready, MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable
- **Capacity / Allocatable** — Kullanılabilir CPU ve memory
- **Allocated resources** — Ne kadar kullanılıyor
- **Events** — Son hatalar

---

## NotReady

### En kritik durum. Node cluster'la konuşamıyor.

```bash
# NotReady node'u bul
kubectl get nodes | grep NotReady

# Önce node'un eventlerine bak
kubectl describe node <node> | grep -A20 "Conditions\|Events"
```

### Olası Nedenler

#### 1. kubelet çalışmıyor
```bash
# Node'a SSH ile bağlan
ssh <node-ip>

# kubelet servisinin durumu
systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager

# Yaygın kubelet hataları:
# "failed to run Kubelet: misconfiguration"  → config dosyası hatası
# "node not found"                           → API server erişim sorunu
# "certificate expired"                       → TLS sertifikası yenilenmeli

# kubelet'i yeniden başlat
systemctl restart kubelet
```

#### 2. Container runtime çalışmıyor
```bash
# containerd durumu
systemctl status containerd

# containerd logları
journalctl -u containerd -n 50 --no-pager

# container listesi (containerd üzerinden)
crictl ps
crictl pods

# Yeniden başlat
systemctl restart containerd
```

#### 3. API Server'a erişim yok (ağ sorunu)
```bash
# Node'dan API server'a bağlantı testi
curl -k https://<control-plane-ip>:6443/healthz

# /etc/hosts ve DNS
cat /etc/hosts
nslookup <control-plane-hostname>

# kube-proxy veya CNI sorunu da olabilir
systemctl status kube-proxy
```

#### 4. Sertifika sorunu
```bash
# kubelet sertifikasını kontrol et
ls -la /var/lib/kubelet/pki/
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates

# Sertifika yenileme (kubeadm cluster)
kubeadm certs check-expiration
kubeadm certs renew all
```

---

## DiskPressure

### Node diski dolmak üzere. Pod eviction başlar.

```bash
# Disk kullanımını gör
df -h          # Partition bazlı
du -sh /var/lib/containerd/*   # Container storage

# Kubernetes eviction thresholds (varsayılan)
# imagefs.available < 15%  → DiskPressure
# nodefs.available < 10%   → DiskPressure

# Hangi container image'lar yer kaplıyor?
crictl images
crictl rmi --prune    # Kullanılmayan image'ları sil

# Docker (eski cluster'larda)
docker system prune -af

# containerd garbage collection
crictl stopp <pod-id>
crictl rmp <pod-id>
```

### Log Şişmesi (En Yaygın Neden)
```bash
# En büyük log dosyaları
find /var/log/pods -name "*.log" -exec du -sh {} \; | sort -rh | head -20

# Bozuk pod log döngüsü — container sürekli crash → dev/null'a büyük log
# Çözüm: Log rotation yapılandır (/etc/logrotate.d/kubernetes)
# veya container'da --log-max-size flag'i kullan
```

---

## MemoryPressure

```bash
# Node bellek durumu
free -h
kubectl top nodes

# Hangi pod'lar en çok bellek tüketiyor?
kubectl top pods -A --sort-by=memory | head -20

# OOM Killer logları (kernel düzeyinde)
dmesg | grep -i "oom\|killed process"
journalctl -k | grep -i oom

# kubelet eviction ile pod'lar çıkarılıyor
kubectl describe node <node> | grep "Evicted\|eviction"
```

### Eviction Politikası Ayarı
```yaml
# kubelet yapılandırması (/var/lib/kubelet/config.yaml)
evictionHard:
  memory.available: "200Mi"   # 200Mi kaldığında eviction başlar
  nodefs.available: "10%"
  imagefs.available: "15%"
evictionSoft:
  memory.available: "500Mi"   # Soft limit — evictionSoftGracePeriod kadar bekler
evictionSoftGracePeriod:
  memory.available: "1m30s"
```

---

## PIDPressure

```bash
# Çok fazla process çalışıyor
kubectl describe node <node> | grep PIDPressure

# Process sayısı
ps aux | wc -l
cat /proc/sys/kernel/pid_max

# Hangi pod'ların fazla process açtığını bul
kubectl top pods -A | sort -k4 -rn
```

---

## Node Draining (Bakım Modu)

Node'u bakıma almak için pod'ları güvenle taşı:

```bash
# Node'u cordon et (yeni pod atanmasını engelle)
kubectl cordon <node>

# Mevcut pod'ları taşı
kubectl drain <node> \
  --ignore-daemonsets \    # DaemonSet pod'larını atla
  --delete-emptydir-data \ # emptyDir volume olan pod'ları da taşı
  --grace-period=60        # Graceful shutdown süresi

# Bakım bitti, node'u geri al
kubectl uncordon <node>
```

> [!WARNING]
> `drain` komutu PodDisruptionBudget (PDB) kısıtlamalarına uyar. PDB min available sayısı karşılanamıyorsa drain takılır. `--force` ile bypass edilebilir ama prod'da dikkatli olun.

---

## Node'a SSH Olmadan Debug

```bash
# kubectl node debug (v1.23+)
kubectl debug node/<node> -it --image=ubuntu

# Node'un dosya sistemine /host altından erişilir
ls /host/var/log/
cat /host/etc/kubernetes/kubelet.conf
journalctl --root=/host -u kubelet -n 100
```

---

## Genel Node Tanı Akışı

```
Node sorunlu
     │
     ├── NotReady
     │     ├── kubelet çalışıyor mu? → systemctl status kubelet
     │     ├── containerd çalışıyor mu? → systemctl status containerd
     │     ├── API Server'a erişim var mı? → curl https://api:6443/healthz
     │     └── Sertifika geçerli mi? → openssl x509 -in ... -noout -dates
     │
     ├── DiskPressure
     │     ├── df -h → hangi partition dolu?
     │     ├── crictl images → image temizliği
     │     └── Pod log şişmesi → find /var/log/pods
     │
     ├── MemoryPressure
     │     ├── kubectl top nodes/pods
     │     ├── dmesg | grep oom
     │     └── Eviction policy ayarla
     │
     └── NetworkUnavailable
           ├── CNI plugin çalışıyor mu?
           └── kubectl get pods -n kube-system | grep cilium/flannel
```
