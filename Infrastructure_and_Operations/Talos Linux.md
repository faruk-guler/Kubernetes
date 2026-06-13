# Talos Linux — Immutable Kubernetes OS

Talos Linux, sadece Kubernetes çalıştırmak için tasarlanmış salt okunur, minimal ve API odaklı bir işletim sistemidir. 2026 itibarıyla production Kubernetes için en güvenli OS seçeneklerinden biridir.

---

## Neden Talos?

```
Geleneksel Linux (Ubuntu/RHEL):
  ❌ SSH erişimi → saldırı yüzeyi
  ❌ Paket yöneticisi (apt/dnf) → unauthorized değişiklik riski
  ❌ Read-write filesystem → kalıcı manipülasyon mümkün
  ❌ Systemd, cron, bash → gereksiz servisler

Talos Linux:
  ✅ SSH yok — sadece API (gRPC + TLS)
  ✅ Paket yöneticisi yok — immutable filesystem
  ✅ Sadece Kubernetes için gerekli bileşenler
  ✅ Her şey API üzerinden yönetilir
  ✅ Atomic update (bir bütün olarak güncellenir, paket paket değil)
```

---

## Kurulum — talosctl CLI

```bash
# talosctl kurulumu
brew install talosctl    # macOS
# Linux:
curl -sL https://talos.dev/install | sh

# Versiyon kontrol
talosctl version --client
```

---

## Local Cluster (Docker / QEMU)

```bash
# Docker üzerinde hızlı test cluster'ı
talosctl cluster create \
  --name dev-cluster \
  --workers 2 \
  --controlplanes 1 \
  --kubernetes-version 1.31.0

# kubeconfig al
talosctl kubeconfig --nodes 10.5.0.2

# Cluster durumu
kubectl get nodes
talosctl -n 10.5.0.2 version
talosctl -n 10.5.0.2 dashboard
```

---

## Bare-Metal / VM Kurulum

```bash
# 1. Talos disk image indir (ISO veya raw)
curl -L https://github.com/siderolabs/talos/releases/download/v1.7.0/metal-amd64.iso \
  -o talos.iso

# 2. Control plane konfigürasyon oluştur
talosctl gen config my-cluster https://192.168.1.100:6443 \
  --output-dir ./talos-config

# Oluşturulan dosyalar:
#   controlplane.yaml  → Control plane node konfigürasyonu
#   worker.yaml        → Worker node konfigürasyonu
#   talosconfig        → talosctl kimlik bilgileri

# 3. Control plane node'unu yapılandır
talosctl apply-config \
  --nodes 192.168.1.100 \
  --file ./talos-config/controlplane.yaml \
  --insecure    # İlk kurulumda TLS yok

# 4. Bootstrap (ilk control plane node)
talosctl bootstrap --nodes 192.168.1.100 \
  --talosconfig ./talos-config/talosconfig

# 5. Worker node'ları ekle
talosctl apply-config \
  --nodes 192.168.1.101 \
  --nodes 192.168.1.102 \
  --file ./talos-config/worker.yaml \
  --insecure

# 6. kubeconfig al
talosctl kubeconfig \
  --nodes 192.168.1.100 \
  --talosconfig ./talos-config/talosconfig
```

---

## MachineConfig — Konfigürasyon Yönetimi

```yaml
# controlplane.yaml — temel yapı
version: v1alpha1
debug: false
persist: true
machine:
  type: controlplane
  token: <generated>
  ca:
    crt: <generated>
    key: <generated>
  kubelet:
    image: ghcr.io/siderolabs/kubelet:v1.31.0
    extraArgs:
      rotate-server-certificates: true
  network:
    hostname: cp-01
    interfaces:
    - interface: eth0
      addresses:
      - 192.168.1.100/24
      routes:
      - network: 0.0.0.0/0
        gateway: 192.168.1.1
      dhcp: false
  install:
    disk: /dev/sda
    image: ghcr.io/siderolabs/installer:v1.7.0
    bootloader: true
    wipe: false
  sysctls:
    net.ipv4.ip_forward: "1"
cluster:
  controlPlane:
    endpoint: https://192.168.1.100:6443
  network:
    dnsDomain: cluster.local
    podSubnets:
    - 10.244.0.0/16
    serviceSubnets:
    - 10.96.0.0/12
  etcd:
    ca:
      crt: <generated>
      key: <generated>
```

```bash
# Konfigürasyon değişikliği uygula (API üzerinden)
talosctl apply-config \
  --nodes 192.168.1.100 \
  --file updated-controlplane.yaml

# Node'u yeniden başlat
talosctl reboot --nodes 192.168.1.100

# Node'u temizle (factory reset)
talosctl reset --nodes 192.168.1.100 --graceful
```

---

## Talos OS Güncelleme

```bash
# Mevcut versiyon
talosctl version --nodes 192.168.1.100

# OS güncelleme (atomic — mevcut versiyon korunur, sorun varsa rollback)
talosctl upgrade \
  --nodes 192.168.1.100 \
  --image ghcr.io/siderolabs/installer:v1.7.0

# Tüm node'ları güncelle
for node in 192.168.1.100 192.168.1.101 192.168.1.102; do
  talosctl upgrade --nodes $node \
    --image ghcr.io/siderolabs/installer:v1.7.0
  sleep 60    # Node hazır olana kadar bekle
done
```

---

## Sorun Giderme

```bash
# Node logları
talosctl logs --nodes 192.168.1.100 kubelet
talosctl logs --nodes 192.168.1.100 containerd

# Dmesg
talosctl dmesg --nodes 192.168.1.100

# Servis durumu
talosctl services --nodes 192.168.1.100

# Dashboard (terminal UI)
talosctl dashboard --nodes 192.168.1.100

# etcd üyelik
talosctl etcd members --nodes 192.168.1.100

# Node'a "exec" — Talos'ta shell yok, ama pod exec var
kubectl exec -it debug-pod -n kube-system -- /bin/sh
```

---

## Talos vs Diğer OS

| Özellik | Talos Linux | Flatcar Linux | Ubuntu |
|:--------|:-----------|:-------------|:-------|
| SSH | ❌ | ✅ | ✅ |
| Shell | ❌ | ✅ | ✅ |
| Paket yöneticisi | ❌ | ❌ | ✅ |
| Immutable FS | ✅ | ✅ | ❌ |
| K8s odaklı | ✅✅ | ❌ | ❌ |
| API yönetim | ✅ | ❌ | ❌ |
| Atomic update | ✅ | ✅ | ❌ |
| CIS Benchmark | ✅ built-in | Kısmen | Manuel |

> [!TIP]
> Talos'ta SSH yoktur ama `talosctl` ile node'a her türlü erişim mümkündür. Loglara, servis durumuna, etcd'ye, hatta konteynerlere API üzerinden erişebilirsiniz.
