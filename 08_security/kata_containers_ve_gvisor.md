# Kata Containers ve gVisor ile Sanal Makine (VM) Seviyesinde İzolasyon

Geleneksel Kubernetes konteynerleri, Linux çekirdeğinin (Kernel) `namespaces` ve `cgroups` yeteneklerini kullanarak birbirlerinden ayrıştırılır. Hızlı ve hafif olmalarına rağmen, tüm konteynerler host (worker node) işletim sisteminin çekirdeğini ortaklaşa paylaşır.

Eğer bir saldırgan konteyner içinden Linux çekirdeğindeki bir açığı (kernel exploit) sömürürse, pod sınırlarından kaçıp fiziksel/sanal sunucunun tamamını ele geçirebilir. Bu riski önlemek ve çoklu kiracılı (multi-tenant) ortamlarda en üst düzey izolasyonu sağlamak amacıyla **Kata Containers** veya **gVisor** gibi sanal makine (VM) düzeyinde koruma sağlayan runtime çözümleri kullanılır.

---

## 1. İzolasyon Katmanlarının Karşılaştırılması

```
Geleneksel Konteyner (runc):
  [ Pod / Container ] ──► [ Container Runtime (runc) ] ──► [ Host Linux Kernel (Paylaşımlı) ]
  * Risk: Çekirdek zafiyetleri tüm node'u etkileyebilir.

Kata Containers:
  [ Pod / Container ] ──► [ MicroVM (QEMU/Firecracker) ] ──► [ Özel Miniature Kernel ] ──► [ Host Kernel ]
  * Çözüm: Her pod, kendine ait tamamen izole edilmiş mini bir sanal makinede çalışır.

gVisor (runsc):
  [ Pod / Container ] ──► [ gVisor (Go tabanlı user-space kernel) ] ──► [ Host Kernel ]
  * Çözüm: Konteynerin sistem çağrıları (syscalls) araya girilerek (intercept) gVisor'ın sanal çekirdeğinde taklit edilir.
```

---

## 2. RuntimeClass CRD Tanımlaması

Kubernetes, pod'ların hangi container runtime (çalışma zamanı) üzerinde çalışacağını belirlemek için **RuntimeClass** kaynaklarını kullanır.

### gVisor için RuntimeClass

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc # Containerd config dosyasındaki handler adı
```

### Kata Containers (QEMU) için RuntimeClass (Overhead Limitli)

Kata microVM'lerinin tükettiği ekstra kaynakları Kubernetes scheduler'a bildirmek için `overhead` alanı tanımlanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kata_containers_ve_gvisor_manifest_1.yaml](../Manifests/07_security/kata_containers_ve_gvisor_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Pod'larda RuntimeClass Kullanımı

Bir podun sanal makine izolasyonuyla çalışması için pod spec tanımına `runtimeClassName` parametresini eklemek yeterlidir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kata_containers_ve_gvisor_manifest_2.yaml](../Manifests/07_security/kata_containers_ve_gvisor_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Kata Containers Kurulumu (QEMU & Firecracker)

### Containerd Yapılandırması

Worker node'larda `/etc/containerd/config.toml` dosyasında Kata runtime kaydedilir:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu]
  runtime_type = "io.containerd.kata-containers.v2"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu.options]
  ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration-qemu.toml"
```

### AWS veya Baremetal için Firecracker Entegrasyonu

Çok hızlı ve düşük kaynak tüketimli microVM'ler için **Firecracker** hypervisor yapılandırması:

```toml
# /opt/kata/share/defaults/kata-containers/configuration-fc.toml
[hypervisor.firecracker]
  path = "/opt/kata/bin/firecracker"
  kernel = "/opt/kata/share/kata-containers/vmlinux.container"
  image = "/opt/kata/share/kata-containers/kata-containers.img"
  default_vcpus = 1
  default_memory = 128 # MB
```

Değişikliklerin ardından containerd servisinin yeniden başlatılması gerekir:

```bash
systemctl restart containerd
```

---

## 5. gVisor Kurulumu ve Doğrulama

gVisor'ın `runsc` aracı node'lara kurulup containerd'ye entegre edildikten sonra test etmek için:

```bash
# 1. gVisor runtime sınıfı ile geçici bir pod çalıştırın ve kernel versiyonunu sorun
kubectl run gvisor-test --image=nginx:alpine \
  --overrides='{"spec":{"runtimeClassName":"gvisor"}}' \
  --rm -it --restart=Never -- uname -r

# Sonuç Çıktısı: 4.4.0 (gVisor'ın fake/taklit çekirdek sürümü)
```

Eğer pod `uname -r` sonucunda sunucunun asıl çekirdek sürümünü (örneğin `6.1.0-amd64`) değil de `4.4.0` veya `4.19.0` gibi sabit bir değer dönüyorsa, gVisor izolasyonunun başarıyla devrede olduğu onaylanmış olur.

---

## 6. Kata vs. gVisor Karşılaştırma Matrisi

| Kriter | Kata Containers | gVisor |
|:---|:---:|:---:|
| **Teknoloji** | Gerçek Donanım Sanallaştırma (QEMU/Firecracker) | User-space Sistem Çağrısı Taklidi (Go tabanlı) |
| **Başlatma Hızı (Overhead)** | ~150 - 250 ms | ~20 - 50 ms |
| **Bellek Tüketimi (Overhead)** | Pod başına ~100-200 MB | Pod başına ~15-50 MB |
| **Syscall Uyumluluğu** | %100 Linux uyumlu | Kısmi (Sadece en sık kullanılan ~250 syscall) |
| **GPU/Sürücü Desteği** | Evet (PCI Passthrough ile) | Hayır |
| **Gelişmiş Sanallaştırma** | İç İçe Sanallaştırma (Nested Virt.) gerekir | Herhangi bir bulut VM üzerinde doğrudan çalışabilir |

---

## 7. Kyverno ile Güvensiz Namespace'lerde Güvenli Runtime Zorunluluğu

Geliştiricilerin `untrusted-workloads` isim alanına (örneğin internetten rastgele kod çalıştıran scriptler) `runc` kullanarak pod açmasını engellemek ve gVisor kullanmaya zorlamak için aşağıdaki Kyverno politikası tanımlanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kata_containers_ve_gvisor_manifest_3.yaml](../Manifests/07_security/kata_containers_ve_gvisor_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 8. Ne Zaman Kullanılmalıdır?

### ✅ Kata Containers Tercih Edilecek Durumlar

* Müşterilerin kendi yazılım kodlarını (arbitrary code) çalıştırdığı çoklu kiracılı SaaS platformları.
* CI/CD Runner yapıları (Geliştiricilerin derleme scriptlerini izole etmek).
* Gelişmiş donanım yetenekleri (GPU) ve özel çekirdek modüllerine doğrudan ihtiyaç duyan kritik iş yükleri.

### ✅ gVisor Tercih Edilecek Durumlar

* Çok fazla podun çalıştığı ve bellek/CPU overhead maliyetlerinin düşük tutulmak istendiği mikroservis mimarileri.
* İç içe sanallaştırma (Nested Virtualization) desteği olmayan AWS/Azure standart VM ortamları.

### ❌ İki Teknolojinin de Uygun Olmadığı Senaryolar

* Yüksek girdi/çıktı (I/O) ve düşük gecikme gerektiren veritabanı (PostgreSQL, Cassandra vb.) ve veri saklama servisleri.
* En yüksek performansla çalışması gereken AI/ML model eğitim (training) süreçleri.
