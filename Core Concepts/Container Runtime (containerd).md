# Container Runtime Deep Dive (containerd)

Kubernetes pod'ları çalıştırmaz — container runtime çalıştırır. Bu katmanı anlamak, `kubectl describe pod` ile `crictl` arasındaki farkı çözmek ve image sorunlarını root-cause'a kadar götürmek için kritik.

---

## Mimari Katmanlar

```
kubectl
  │
  ▼
kube-apiserver
  │
  ▼
kubelet (her node'da)
  │ CRI (Container Runtime Interface) — gRPC
  ▼
containerd
  │ OCI Runtime Spec
  ▼
runc (veya kata-containers, gVisor)
  │ Linux kernel syscalls
  ▼
cgroups + namespaces (Linux kernel)
```

---

## CRI — Container Runtime Interface

kubelet doğrudan Docker veya containerd API'sini çağırmaz. **CRI** adlı standart gRPC arayüzü üzerinden konuşur:

```
kubelet → CRI gRPC →  containerd shim
                       └── runc (container başlat)
```

```bash
# Kubernetes hangi runtime kullanıyor?
kubectl get node <node> -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}'
# containerd://1.7.13
```

---

## containerd Bileşenleri

```
containerd (daemon)
  ├── snapshotter   → Image katmanlarını dosya sistemi olarak yönetir
  ├── content store → Image blob'larını saklar (/var/lib/containerd/io.containerd.content.v1.content)
  ├── image store   → Metadata (isim, tag, digest)
  ├── container     → Running container state
  └── task          → Çalışan process (runc ile başlatılan)
```

```bash
# containerd namespace'leri
# Kubernetes pod'ları → k8s.io namespace
# Docker → moby namespace
ctr namespace list
# NAME    LABELS
# k8s.io
# moby
```

---

## crictl — Kubernetes Container Debug Aracı

```bash
# crictl kurulumu (zaten node'larda var)
which crictl  # /usr/local/bin/crictl

# Runtime bağlantısı
crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps

# Çalışan container'lar
crictl ps

# Tüm container'lar (stopped dahil)
crictl ps -a

# Pod'lar
crictl pods

# Image listesi
crictl images

# Container logları
crictl logs <container-id>
crictl logs --tail=50 <container-id>

# Container içine gir
crictl exec -it <container-id> sh

# Container inspect
crictl inspect <container-id>

# Image pull (registry'den)
crictl pull nginx:1.25

# Image sil
crictl rmi <image-id>

# Kullanılmayan image'ları sil (disk temizliği)
crictl rmi --prune
```

---

## Image Katmanları ve Depolama

```bash
# Image'ın katmanlarını gör
ctr -n k8s.io images ls
ctr -n k8s.io content ls | head -10

# Snapshot'ları gör (çalışan container dosya sistemi)
ctr -n k8s.io snapshots ls

# Image boyutu analizi
du -sh /var/lib/containerd/
# io.containerd.content.v1.content/  ← Ham blob'lar (sıkıştırılmış)
# io.containerd.snapshotter.v1.overlayfs/ ← Aktif katmanlar

# Overlay filesystem'i gör (container başladığında)
mount | grep overlay
# overlay on /run/containerd/.../rootfs type overlay
#   (rw,lowerdir=<base layers>,upperdir=<container changes>,workdir=...)
```

### Copy-on-Write Mekanizması

```
Image katmanları (read-only):
  Layer 3: /app/server  (eklendi)
  Layer 2: /usr/bin/python  (eklendi)
  Layer 1: /etc/os-release  (base image)

Container çalışınca:
  upperdir (read-write):  Container'ın değişiklikleri
  lowerdir (read-only):   Image katmanları (paylaşımlı)

  10 pod aynı image'ı çalıştırıyor → Image katmanları TEK KOPYADA
  Sadece her pod'un upperdir'i ayrı → Disk tasarrufu
```

---

## Image Pull Süreci

```
kubelet → containerd.pull(image)
            │
            1. Registry'den manifest.json çek
            2. Manifest'teki her katman digest'i kontrol et
            3. Content store'da yoksa çek (paralel)
            4. Decompress (gzip → tar)
            5. Snapshot'a unpack et
            6. Image metadata kaydet
```

```bash
# Image pull süreci izle
journalctl -u containerd --follow | grep -i pull

# Image pull başarısız mı?
crictl pull ghcr.io/company/app:v2
# ERRO[0000] pulling image failed  err="...unauthorized..."
# → Registry auth sorunu

# Image registry credentials
kubectl get secret regcred -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

---

## Container Başlatma Süreci

```bash
# Pod oluşturulduğunda:
1. kubelet → CRI CreatePodSandbox (pause container — network NS)
2. kubelet → CRI PullImage
3. kubelet → CRI CreateContainer
4. kubelet → CRI StartContainer → containerd → runc → process başlat

# Bu süreci izle (node'da)
journalctl -u kubelet --follow | grep -E "Creating|Started|sandbox"

# Pause container nedir?
crictl ps | grep pause
# Kubernetes'te her pod'un network/IPC namespace'ini tutan "infra container"
# Pod silinene kadar çalışır, diğer container'lar buna eklenir
```

---

## Disk Baskısı ve Eviction

```bash
# Disk doluluk kontrolü
df -h /var/lib/containerd

# Image temizliği (kullanılmayan)
crictl rmi --prune

# Log rotasyonu (varsayılan: 100MB, 5 dosya)
ls /var/log/pods/

# kubelet disk eviction eşiği
cat /var/lib/kubelet/config.yaml | grep -A5 eviction
# evictionHard:
#   imagefs.available: 15%    ← %15 altına düşerse image temizler
#   nodefs.available: 10%     ← %10 altına düşerse pod'ları tahliye eder
```

---

## Kata Containers — Güvenli Runtime

Tam VM izolasyonu sağlar, runc yerine Firecracker/QEMU kullanır:

```yaml
# RuntimeClass ile güvenli runtime seç
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-containers
handler: kata

---
# Pod'da kullan (güvenlik kritik workload'lar için)
spec:
  runtimeClassName: kata-containers
  containers:
  - name: sensitive-app
    image: ghcr.io/company/payment-processor:v1
```
