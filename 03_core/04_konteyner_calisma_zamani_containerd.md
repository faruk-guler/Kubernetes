# Konteyner Çalışma Zamanı (Container Runtime - containerd)

Kubernetes pod'ları doğrudan kendi başına çalıştırmaz; bu işi **Container Runtime (Konteyner Çalışma Zamanı)** üstlenir. Bu katmanı anlamak, `kubectl describe pod` çıktıları ile düğümlerde (nodes) doğrudan `crictl` kullanmak arasındaki farkı çözmek ve imaj (image) kaynaklı sorunların kök nedenlerini (root-cause) bulmak için kritiktir.

---

## 1. Mimari Katmanlar

Kubernetes API'sinden işletim sistemi çekirdeğine (kernel) kadar olan akış şu şekildedir:

```
kubectl (Kullanıcı)
  │
  ▼
kube-apiserver (Kontrol Düzlemi)
  │
  ▼
kubelet (Her düğümde çalışan ajan)
  │ CRI (Container Runtime Interface) — gRPC
  ▼
containerd (Çalışma Zamanı Yöneticisi)
  │ OCI Runtime Spec (Açık Standartlar)
  ▼
runc (Konteyneri fiilen başlatan alt motor)
  │ Linux Kernel Syscalls
  ▼
cgroups + namespaces (Çekirdek Düzeyinde İzolasyon)
```

---

## 2. CRI (Container Runtime Interface) Nedir?

kubelet, doğrudan Docker veya containerd API'lerini çağırmaz. Bunun yerine **CRI** adı verilen standartlaştırılmış bir gRPC arayüzü üzerinden konuşur:

```
kubelet ──► CRI gRPC Arayüzü ──► containerd shim ──► runc (İşlemi başlat)
```

Kümenizin hangi çalışma zamanını kullandığını sorgulamak için:

```bash
kubectl get node <dugum-adi> -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}'
# Çıktı Örneği: containerd://1.7.13
```

---

## 3. containerd Bileşenleri ve Yapısı

containerd arka planda çalışan bir daemon servisidir ve şu alt birimlerden oluşur:

* **Snapshotter:** İmaj katmanlarını yöneterek bunları konteynerler için okunabilir/yazılabilir dosya sistemlerine dönüştürür (Varsayılan olarak `overlayfs` kullanılır).
* **Content Store:** İmajların sıkıştırılmış ham dosyalarını (blob'ları) `/var/lib/containerd/io.containerd.content.v1.content` altında saklar.
* **Image Store:** İmajlara ait metadata bilgilerini (tag, digest, isim) tutar.
* **Task:** Konteyner içinde çalışan gerçek süreçleri (processes) temsil eder.

### containerd Namespace Mantığı

containerd, imajları ve konteynerleri mantıksal bölümlere ayırmak için `namespace` kullanır. Kubernetes pod'ları her zaman `k8s.io` namespace'i içinde çalıştırılır:

```bash
# containerd namespace'lerini listeleme
ctr namespace list
# NAME    LABELS
# k8s.io
# moby    (Docker için kullanılır)
```

---

## 4. `crictl` ile Düğüm Seviyesinde Hata Ayıklama (Debug)

`crictl`, Kubernetes CRI uyumlu tüm çalışma zamanlarını (containerd, CRI-O) düğüm üzerinden doğrudan yönetmek ve debug yapmak için kullanılan CLI aracıdır.

> [!TIP]
> **Önemli Kural:** Düğüm üzerinde `crictl` kullanırken, Kubernetes podlarını görebilmek için crictl'in CRI soketine bağlı olması gerekir. Soket ayarı `/etc/crictl.yaml` dosyasında tanımlanır.

### Sık Kullanılan `crictl` Komutları

```bash
# Soket belirterek çalışan konteynerleri listeleme
crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps

# Çalışan podları listeleme
crictl pods

# Düğümdeki tüm imajları listeleme
crictl images

# Konteyner loglarını canlı takip etme
crictl logs <container-id>
crictl logs --tail=50 <container-id>

# Konteynerin içine terminal açarak girme
crictl exec -it <container-id> sh

# Konteyner detaylarını (env, mount vb.) görüntüleme
crictl inspect <container-id>

# Düğüm seviyesinde imaj çekme
crictl pull nginx:1.25

# Kullanılmayan tüm imajları silerek disk alanı açma
crictl rmi --prune
```

---

## 5. İmaj Katmanları ve Copy-on-Write (CoW) Mantığı

Konteynerler disk alanından tasarruf etmek için **Copy-on-Write (CoW)** mekanizmasını kullanır:

```
İmaj Katmanları (Sadece Okunabilir - lowerdir):
  [Katman 3]: Uygulama Kodları (/app/server)
  [Katman 2]: Bağımlılıklar (/usr/bin/python)
  [Katman 1]: İşletim Sistemi Tabanı (Ubuntu Base)

Konteyner Başlatıldığında:
  [Yazılabilir Katman (upperdir)]: Konteynerin çalışma anındaki değişiklikleri
```

* Kümede 10 adet pod aynı imajı çalıştırsa bile, imaj katmanları (`lowerdir`) diskte sadece tek bir kopya olarak tutulur. Her pod'un yaptığı yazma işlemleri kendi bağımsız yazılabilir katmanına (`upperdir`) yazılır. Bu durum disk alanından muazzam tasarruf sağlar.

Düğüm üzerindeki disk kullanımını ve bağlanan overlay dosya sistemlerini incelemek için:

```bash
# Disk alanı analizi
du -sh /var/lib/containerd/

# Overlay mount noktalarını kontrol etme
mount | grep overlay
```

---

## 6. Düğüm Disk Baskısı (Disk Pressure) ve Tahliye (Eviction)

Eğer düğümün diski aşırı dolarsa, kubelet düğümü korumak amacıyla kullanılmayan imajları siler veya podları tahliye (eviction) eder.

Bu sınırlar `/var/lib/kubelet/config.yaml` dosyasından yapılandırılır:

```yaml
evictionHard:
  imagefs.available: "15%"  # Düğüm diski %15'in altına düşerse kullanılmayan imajları temizle
  nodefs.available: "10%"   # Sistem diski %10'un altına düşerse podları başka düğümlere taşı (Evict)
```

---

## Özet

Kubernetes düğümlerinde sorun yaşandığında, API Server çalışmasa bile düğüme SSH ile bağlanıp **`crictl`** kullanarak containerd seviyesinde podların ve konteynerlerin durumunu doğrudan izleyebilir, imaj çekme hatalarını ve disk doluluk problemlerini hızla çözebilirsiniz.
