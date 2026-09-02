# Talos Linux ile Salt Okunur Kubernetes İşletim Sistemi (Talos Linux Guide)

**Talos Linux**, yalnızca Kubernetes çalıştırmak amacıyla sıfırdan tasarlanmış, salt okunur (read-only), minimal, immutable (değiştirilemez) ve tamamen API odaklı (API-driven) modern bir Linux dağıtımıdır. 2026 yılı itibarıyla, güvenlik yüzeyini en aza indirgemek isteyen üretim (production) Kubernetes altyapıları için en popüler işletim sistemi alternatifidir.

---

## 1. Neden Talos Linux?

Geleneksel Linux dağıtımları (Ubuntu, RHEL) genel amaçlı sunuculardır ve içinde SSH, paket yöneticileri, cron, systemd gibi Kubernetes için gerekli olmayan yüzlerce araç barındırır. Bu durum hem saldırı yüzeyini genişletir hem de düğümlerin durumlarında tutarsızlıklara (**configuration drift**) yol açar.

```
Geleneksel İşletim Sistemi (Ubuntu/Debian):
  ❌ SSH Erişimi ──► Saldırganlar için ilk hedef.
  ❌ Paket Yöneticisi (apt/dnf) ──► Yetkisiz yazılım yükleme riski.
  ❌ Yazılabilir Dosya Sistemi ──► Çekirdek dosyalarının değiştirilebilmesi.
  ❌ Fazladan Servisler (systemd, cron) ──► Gereksiz kaynak tüketimi ve güvenlik riski.

Talos Linux:
  ✅ SSH Yok ──► Düğümler sadece API (gRPC + TLS) üzerinden yönetilir.
  ✅ Paket Yöneticisi Yok ──► Tamamen salt okunur (immutable) dosya sistemi.
  ✅ Sadece Kubernetes Bileşenleri ──► Ekstra çalışan tek bir gereksiz servis yoktur.
  ✅ Atomik Güncelleme ──► OS güncellemeleri paket paket değil, tek seferde imaj olarak kurulur (Hata anında otomatik rollback).
```

---

## 2. Kurulum — `talosctl` CLI

Talos Linux sunucularını yönetmek için kendi komut satırı aracı olan `talosctl` kurulmalıdır:

```bash
# Linux sistemlerde talosctl kurulumu
curl -sL https://talos.dev/install | sh

# Versiyon kontrolü
talosctl version --client
```

---

## 3. Lokal Küme Oluşturma (Docker/QEMU)

Kendi bilgisayarınızda Talos Linux deneyimi kazanmak amacıyla Docker üzerinde hızlıca test kümesi ayağa kaldırabilirsiniz:

```bash
# Docker üzerinde lokal Talos kümesi oluşturun
talosctl cluster create \
  --name talos-dev-cluster \
  --workers 2 \
  --controlplanes 1 \
  --kubernetes-version 1.32.0

# Kümenin kubeconfig dosyasını çekin
talosctl kubeconfig --nodes 10.5.0.2

# Kubernetes düğümlerini kontrol edin
kubectl get nodes
```

---

## 4. Gerçek Sunucular (Bare-Metal / VM) Üzerinde Kurulum

Fiziksel veya sanal sunucularda sıfırdan Talos kurulumu gerçekleştirmek için şu adımlar takip edilir:

### Adım 1: Talos ISO İmajının İndirilmesi

Sunucularınızı boot etmek için en güncel ISO dosyasını indirin ve sunuculara bağlayarak başlatın:

```bash
curl -L https://github.com/siderolabs/talos/releases/download/v1.7.0/metal-amd64.iso -o talos.iso
```

### Adım 2: Konfigürasyon Dosyalarının Üretilmesi

Talos işletim sisteminin tüm ayarları YAML dosyalarıyla yönetilir. Master sunucunun IP adresini belirterek konfigürasyonu üretin:

```bash
talosctl gen config my-k8s-cluster https://192.168.10.10:6443 --output-dir ./talos-config
```

Bu komut belirtilen dizine 3 dosya üretir:

* `controlplane.yaml`: Master düğümler için ayarlar.
* `worker.yaml`: Worker düğümler için ayarlar.
* `talosconfig`: Sunucuları dışarıdan yönetmek için kullanacağınız kimlik bilgisi dosyası.

### Adım 3: İlk Master Düğümüne Konfigürasyonun Gönderilmesi

```bash
# Sunucuda henüz TLS aktif olmadığından ilk seferde --insecure parametresiyle gönderilir
talosctl apply-config \
  --nodes 192.168.10.10 \
  --file ./talos-config/controlplane.yaml \
  --insecure
```

### Adım 4: Bootstrap İşlemi (Kümenin İlk Kez Başlatılması)

Sadece ilk master sunucu üzerinde bootstrap komutunu tetikleyerek Kubernetes API'sini ayağa kaldırın:

```bash
talosctl bootstrap --nodes 192.168.10.10 --talosconfig ./talos-config/talosconfig
```

### Adım 5: Worker Düğümlerinin Yapılandırılması

```bash
talosctl apply-config \
  --nodes 192.168.10.11 \
  --nodes 192.168.10.12 \
  --file ./talos-config/worker.yaml \
  --insecure
```

### Adım 6: Kubeconfig Dosyasının Alınması

Küme ayağa kalktıktan sonra, yönetici bağlantı dosyasını yerel makinenize çekebilirsiniz:

```bash
talosctl kubeconfig \
  --nodes 192.168.10.10 \
  --talosconfig ./talos-config/talosconfig
```

---

## 5. MachineConfig — Konfigürasyon Güncellemeleri

İşletim sistemi düzeyindeki tüm kernel parametresi veya containerd ayarları, doğrudan `talosctl` üzerinden API vasıtasıyla dinamik olarak güncellenir:

```bash
# Güncellenen konfigürasyon dosyasını düğüme gönderin
talosctl apply-config \
  --nodes 192.168.10.10 \
  --file updated-controlplane.yaml

# Düğümü API üzerinden yeniden başlatın
talosctl reboot --nodes 192.168.10.10

# Düğümü fabrika ayarlarına sıfırlayın (Factory Reset)
talosctl reset --nodes 192.168.10.10 --graceful
```

---

## 6. Atomik OS Güncelleme (OS Upgrade)

Talos Linux, işletim sistemini dosya dosya güncellemek yerine tüm sistemi tek bir imaj olarak günceller:

```bash
# Sunucunun işletim sistemini yeni sürüme yükseltin
talosctl upgrade \
  --nodes 192.168.10.10 \
  --image ghcr.io/siderolabs/installer:v1.7.0
```

---

## 7. SSH Olmadan Sorun Giderme (Troubleshooting via talosctl)

SSH bağlantısı ve shell olmasa dahi, `talosctl` aracının sunduğu gelişmiş API komutlarıyla her türlü teşhis işlemi yapılabilir:

```bash
# 1. Kubelet ve containerd servis loglarını okuma
talosctl logs --nodes 192.168.10.10 kubelet
talosctl logs --nodes 192.168.10.10 containerd

# 2. Kernel loglarını (dmesg) okuma
talosctl dmesg --nodes 192.168.10.10

# 3. Çalışan tüm OS servislerini listeleme
talosctl services --nodes 192.168.10.10

# 4. Terminal tabanlı Dashboard'u açma (Anlık CPU/RAM izleme)
talosctl dashboard --nodes 192.168.10.10

# 5. etcd üyelerinin durumunu kontrol etme
talosctl etcd members --nodes 192.168.10.10
```

---

## 8. İşletim Sistemleri Karşılaştırma Tablosu

| Özellik | Talos Linux | Flatcar Linux | Ubuntu Server |
|:---|:---:|:---:|:---:|
| **SSH Erişimi** | ❌ Yok | ✅ Var | ✅ Var |
| **Kullanıcı Kabuğu (Shell)** | ❌ Yok | ✅ Var | ✅ Var |
| **Paket Yöneticisi** | ❌ Yok | ❌ Yok | ✅ Var (`apt`) |
| **Salt Okunur (Immutable)** | ✅ Evet | ✅ Evet | ❌ Hayır |
| **Kubernetes Odaklılık** | ✅ Dedicated | 🟡 Genel Amaçlı | 🟡 Genel Amaçlı |
| **API Tabanlı Yönetim** | ✅ Evet | ❌ Hayır | ❌ Hayır |
| **Bütünsel OS Güncelleme** | ✅ Evet | ✅ Evet | ❌ Hayır |
| **Yerleşik CIS Benchmark** | ✅ Evet | ❌ Hayır | ❌ Hayır |

---

## Özet

Talos Linux, Kubernetes çalıştırmak için gereksiz tüm Linux mirasını kenara bırakarak en güvenli ve en kararlı düğüm altyapısını kurmanızı sağlar. **SSH ve shell erişiminin olmaması** ilk başta alışkanlıkları değiştirse de, sunduğu **`talosctl` API** yetenekleri ve sıfır-bakım (zero-maintenance) yapısı, büyük ölçekli canlı ortamlarda operasyonel yükleri devasa oranda azaltmaktadır.
