# Linux Çekirdeği Seviyesinde Konteyner İzolasyonu (Namespaces & PivotRoot)

Konteynerler, Sanal Makineler (Virtual Machines) gibi donanım seviyesinde sanallaştırma yapmazlar. Konteynerler, ana makinenin (host) işletim sistemi çekirdeğini (kernel) paylaşan ve sadece **çekirdek seviyesindeki belirli soyutlama mekanizmalarıyla izole edilmiş normal Linux süreçleridir (processes).**

Bu izolasyonun arka planda nasıl sağlandığını anlamak, Kubernetes ve konteyner güvenliğinin temelini oluşturur.

---

## 1. Linux Namespaces (İsim Uzayları)

Bir sürecin neleri görebileceğini (görüş alanını) sınırlayan çekirdek özelliğidir. Linux çekirdeğinde 8 farklı namespace türü bulunur:

| Namespace Türü | Neyi İzole Eder? | Konteynerdeki Karşılığı |
| :--- | :--- | :--- |
| **PID (Process ID)** | Süreç Kimlikleri | Konteyner içindeki uygulamanın kendisini PID 1 (başlangıç süreci) olarak görmesini sağlar. Hosttaki diğer süreçleri gizler. |
| **NET (Network)** | Ağ Arayüzleri, Portlar | Konteynerin kendi özel sanal ağ kartına (veth pair), IP adresine ve routing tablosuna sahip olmasını sağlar. |
| **MNT (Mount)** | Dosya Sistemi Bağlantıları | Konteynerin hosttan bağımsız, kendine özel bir dosya sistemi hiyerarşisine sahip olmasını sağlar. |
| **IPC (Inter-Process)** | Süreçler Arası İletişim | Konteyner içindeki süreçlerin sadece kendi aralarında paylaşımlı bellek (shared memory) kullanabilmesini sağlar. |
| **UTS (Unix Timesharing)** | Hostname ve Domain | Konteynerin hosttan bağımsız bir bilgisayar adı (hostname) almasını sağlar. |
| **USER** | Kullanıcı ve Grup ID'leri | Konteyner içindeki `root` (UID 0) kullanıcısının, host makine üzerinde yetkisiz sıradan bir kullanıcıya (Örn: UID 10005) eşlenmesini sağlar (Rootless konteynerler). |

---

## 2. cgroups (Control Groups - Kontrol Grupları)

Namespaces bir sürecin **neleri görebileceğini** belirlerken, **cgroups** o sürecin **ne kadar kaynak tüketebileceğini** (CPU, RAM, I/O, Network bant genişliği) belirler. 

Kubernetes'te pod'lara koyduğumuz `resources.limits.cpu` ve `resources.limits.memory` limitleri, container runtime (containerd/CRI-O) tarafından doğrudan Linux `cgroups` kurallarına dönüştürülerek kernel seviyesinde uygulanır.

---

## 3. chroot ve pivot_root: Dosya Sistemi Sınırları

Bir sürecin sadece kendine ayrılmış bir klasörü (örneğin `/var/lib/containers/rootfs`) kendi kök dizini (`/`) olarak görmesini sağlamak için dosya sistemi seviyesinde izolasyon gerekir. Bunun için Linux'te iki yöntem vardır:

### A. chroot (Change Root)
En eski yöntemdir. Bir sürecin ve onun alt süreçlerinin kök dizinini değiştirir. Ancak **chroot tam bir güvenlik mekanizması değildir.**

#### chroot Escape (Kaçış) Zafiyeti:
Eğer `chroot` ile izole edilmiş bir süreç `root` yetkilerine sahipse ve chroot çağrılmadan önce açık bir dosya tanımlayıcısı (file descriptor) varsa, `fchdir()` sistem çağrısını kullanarak kolayca chroot sınırlarının dışına çıkıp host işletim sisteminin gerçek kök dizinine erişebilir.

📌 **Zafiyet C Kodu:** Bu kaçış mekanizmasını ve chroot'un neden güvensiz olduğunu gösteren C kod bloğunu [chroot_escape.c](../Manifests/02_containers/chroot_escape.c) dosyasından inceleyebilirsiniz.

---

### B. pivot_root: Güvenli Konteyner Standardı

`chroot`'un zafiyetlerinden dolayı, modern konteyner motorları (runc, crun vb.) dosya sistemi izolasyonu için **`pivot_root`** sistem çağrısını kullanır.

`pivot_root`, mevcut mount namespace içindeki **kök mount noktasını (root mount point) tamamen yeni bir dizinle değiştirir** ve eski kök dizini yeni kök dizininin altındaki geçici bir klasöre taşır (daha sonra bu eski kök dizin umount edilerek tamamen silinir).

#### Neden pivot_root Daha Güvenli?
* `pivot_root` sadece dosya yolu çözümlemesini değil, **mount namespace seviyesinde mount tablosunu tamamen değiştirir.**
* İşlem tamamlandıktan sonra eski kök dizine ait tüm referanslar (`umount` edilerek) yok edildiği için, süreç `fchdir()` veya başka yöntemlerle host dosya sistemine geri sızamaz.
