# Pod Kavramı

Kubernetes dünyasının en küçük, en temel ve bölünemez yapı taşı **Pod**'dur.

İlk öğrenme aşamasında genellikle "Pod = Konteyner" yanılgısına düşülür. Ancak Kubernetes doğrudan konteynerleri (Örn: Docker imajlarını) çalıştırmaz; konteynerleri bir kapsülün, yani Pod'un içine koyarak çalıştırır.

Bir Pod; aynı ağı (IP adresini), aynı depolama alanını (Volumes) ve aynı yaşam döngüsünü paylaşan bir veya daha fazla konteynerin oluşturduğu mantıksal bir gruptur.

> **Neden Direkt Konteyner Değil de Pod?**
> Eğer bir web sunucunuz (Nginx) ve bu sunucunun loglarını okuyup merkezi bir yere gönderen bir log toplayıcınız (Filebeat) varsa, bu iki uygulamanın aynı IP adresini ve diski kullanması, birlikte açılıp birlikte kapanması gerekir. Pod mekanizması bu "Simbiyotik (Ortak) Yaşamı" mümkün kılar.

---

## 1. Çoklu Konteyner (Multi-container) Pod'lar ve İleri Seviye Kalıplar

Bir Pod içinde tek bir konteyner çalıştırmak en yaygın senaryodur. Ancak yukarıdaki örnekte olduğu gibi aynı Pod içinde birden fazla konteyner çalıştırmanın bazı çok güçlü mimari kalıpları (patterns) vardır:

### A. Init Containers (Hazırlık Konteynerleri)

Ana uygulamanız ayağa kalkmadan *önce* çalışıp işini bitiren özel konteynerlerdir.

- Örneğin; "Ana web uygulaması başlamadan önce, Init Container veritabanının hazır olup olmadığını 3 saniyede bir kontrol etsin (ping). Veritabanı hazır olunca kapanıp sırayı ana uygulamaya devretsin."
- Kuralları: Başarıyla bitmek (`exit 0`) zorundadırlar, yoksa ana uygulama asla başlamaz.

### B. Sidecar Containers (Yardımcı Konteynerler)

Ana uygulamayla aynı anda çalışan ve ona destek veren konteynerlerdir (Log toplama, proxy yapma vb.).
> [!IMPORTANT]
> **Native Sidecar Desteği (K8s v1.29+):** Eskiden sidecar konteynerlerin başlama sırasını kontrol etmek imkansızdı. Artık `initContainers` kısmına bir konteyner ekleyip `restartPolicy: Always` derseniz, Kubernetes bunu "Native Sidecar" olarak tanır. Ana uygulamadan önce başlar, ama işini bitirip kapanmak yerine ana uygulamayla birlikte sonsuza kadar çalışmaya devam eder.

### C. Static Pods (Statik Pod'lar)

Normalde pod'ları API Server oluşturur. Statik Pod'lar ise API Server'ı atlayarak, doğrudan Node'un içindeki `Kubelet` tarafından diskteki bir YAML dosyasından (genellikle `/etc/kubernetes/manifests`) okunarak başlatılırlar. Kubernetes'in kendi kontrol düzlemi bileşenleri (API Server, etcd) statik pod olarak çalışır.

### D. Ephemeral Containers (Geçici Debug Konteynerleri)

Üretim ortamlarındaki güvenli imajlarda (Distroless vb.) bash, curl gibi araçlar bulunmaz. Uygulamanız çöktüğünde içine girip bakamazsınız. Pod'u yeniden başlatmak da hatayı yok eder.
İşte burada "Geçici Konteynerler" devreye girer. Çalışan, donmuş bir pod'un içine dışarıdan içi araçlarla dolu (Örn: `busybox` veya `netshoot`) bir konteyner enjekte edersiniz:

```bash
# Donmuş olan nginx pod'unun içine netshoot imajını enjekte et
kubectl debug -it nginx-pod --image=nicolaka/netshoot --target=nginx
```

Bu sayede orijinal pod'u bozmadan ve yeniden başlatmadan canlı ameliyat (troubleshooting) yapabilirsiniz.

---

## 2. Pod Yaşam Döngüsü (Lifecycle)

Bir Pod ölümlüdür. Doğar, yaşar ve ölür. Bir Pod silindiğinde veya hata verdiğinde, Kubernetes onu "iyileştirmez", çöpe atıp yerine **yepyeni bir Pod** oluşturur.

Bir Pod oluşturma isteği gönderdiğinizde (API Server'a YAML dosyasını yolladığınızda), Pod şu fazlardan geçer:

1. **Pending (Beklemede):** Kubernetes isteğinizi kabul etti ancak Pod henüz bir sunucuya (Node) atanamadı. Ya kümede yeterli CPU/Bellek yoktur (kaynak bekleniyordur) ya da imaj internetten indiriliyordur.
2. **Running (Çalışıyor):** Pod bir sunucuya atandı. İçindeki konteynerler başarıyla oluşturuldu ve en az biri şu an aktif olarak çalışıyor.
3. **Succeeded (Başarılı):** İçindeki konteynerler görevini başarıyla tamamlayıp (`exit 0`) kendi istekleriyle kapandılar. (Bu durum genellikle sürekli çalışan web sunucularında değil, kısa süreli `Job` nesnelerinde görülür).
4. **Failed (Başarısız):** Konteynerlerden en az biri hata vererek (`exit 1`) çöktü veya sistem tarafından zorla kapatıldı (OOM - Out of Memory vb.).
5. **Unknown (Bilinmeyen):** Node ile bağlantı koptu. Kubernetes, Kubelet'ten haber alamadığı için pod'un akıbetini bilemiyor.

> [!WARNING]
> Eğer `kubectl get pods` dediğinizde **CrashLoopBackOff** hatası görüyorsanız, bu bir faz değildir; uygulamanızın kodunun hata verdiği, çöktüğü ve Kubernetes'in onu sürekli yeniden başlatmaya çalıştığı, ancak uygulamanın tekrar tekrar çöktüğü bir kısırdöngüdür. Sorun altyapıda değil, muhtemelen sizin yazdığınız koddadır (Yanlış veritabanı şifresi vs.).

Pod'lar ölümlü oldukları için doğrudan kullanılmaları çok tehlikelidir. Çöken bir Pod'un yerine yenisini açacak, versiyon güncellemelerini yönetecek bir üst düzey yöneticiye ihtiyacımız vardır.

Bir sonraki bölümde, Pod'ların yöneticisi olan **Deployment** ve **ReplicaSet** nesnelerini inceleyeceğiz.
