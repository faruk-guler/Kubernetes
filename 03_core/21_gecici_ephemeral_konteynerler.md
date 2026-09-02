# Geçici Konteynerler (Ephemeral Containers)

Ephemeral (geçici) container'lar, **çalışan bir pod'a sonradan eklenen** ve yalnızca sorun giderme (debugging) ve teşhis amacıyla kullanılan geçici konteynerlerdir. Kubernetes v1.25 sürümü ile birlikte tamamen kararlı (**Stable - GA**) duruma gelmiştir.

---

## 1. Neden Geçici Konteynerlere İhtiyaç Duyarız?

Modern cloud-native dünyasında, güvenlik ve performans amacıyla imajların olabildiğince minimal tutulması (örneğin; **distroless** veya sadece uygulamanın derlenmiş ikilisini barındran minimal Alpine imajları) standarttır. Bu imajlarda `bash`, `curl`, `dig`, `netstat`, `nslookup` gibi temel ağ ve sistem analiz araçları bulunmaz.

Sorun giderme anında şu engellerle karşılaşılır:

* **`kubectl exec` yetersiz kalır:** Konteynerin içinde analiz yapacak komutlar/araçlar yoktur.
* **Pod'u yeniden başlatmak debug verisini yok eder:** Sorunun kaynağı veya bellek sızıntısı durumu pod yeniden başlayınca kaybolur.
* **Debug imajıyla yeni pod açmak durumu çözmeyebilir:** Hata sadece o an aktif olan pod'un üzerinde veya o spesifik düğümde gerçekleşiyor olabilir.

**Ephemeral container**, çalışan pod'u durdurmadan veya yeniden başlatmadan içine harici bir araç kutusu enjekte ederek bu sorunları giderir.

---

## 2. Kullanım ve Temel Komutlar

`kubectl debug` komutu aracılığıyla çalışan podların içine geçici konteynerler ekleyebiliriz:

```bash
# 1. Temel Kullanım - 'netshoot' imajı ile çalışan pod üzerinde ağ analizi yapma
kubectl debug -it <pod-adi> --image=nicolaka/netshoot --target=<hedef-konteyner-adi>

# Örnek: 'production-api' podunun 'api' konteynerine bağlanma
kubectl debug -it production-api-7d4f9b --image=nicolaka/netshoot --target=api

# 2. BusyBox imajı ile basit dosya sistemi ve DNS kontrolleri
kubectl debug -it web-pod --image=busybox:1.36 --target=web-app

# 3. Pod'u kopyalayarak debug yapma (Orijinal pod'un çalışmasını bozmadan)
kubectl debug nginx-pod -it --image=ubuntu:22.04 --copy-to=debug-pod --share-processes
```

### Popüler Teşhis ve Hata Ayıklama İmajları

| İmaj | İçerdiği Başlıca Araçlar | Kullanım Amacı |
| :--- | :--- | :--- |
| **`nicolaka/netshoot`** | `curl`, `dig`, `nmap`, `tcpdump`, `iperf`, `ss`, `netstat`, `htop` | Gelişmiş ağ ve sistem analizi |
| **`busybox:1.36`** | `sh`, `wget`, `nslookup`, `ping`, `cat` | Temel DNS ve dosya kontrolleri |
| **`ubuntu:22.04`** | `apt-get` paket yöneticisi | Özelleştirilmiş harici araç kurulumları |
| **`alpine:3.19`** | `apk` paket yöneticisi, `sh` | Hafif ve hızlı sorun giderme |

---

## 3. Ephemeral Container Özellikleri ve Kısıtlamaları

Geçici konteynerlerin mimari yapıları normal konteynerlerden farklıdır ve bazı kısıtlamaları vardır:

* **Kaynak Garantisi Yoktur:** `resources` (requests/limits) tanımlanamaz. Kümedeki boş kaynakları kullanırlar.
* **Ağ ve Kapı (Port) Tanımları:** `ports` tanımlanamaz. Ayrıca `livenessProbe` veya `readinessProbe` gibi denetimler desteklenmez.
* **Otomatik Yeniden Başlatma Yoktur:** Eğer geçici konteyner sonlanırsa, Kubernetes bunu otomatik olarak yeniden başlatmaz.
* **Kalıcıdır (Silinemez):** Pod'a bir kere ephemeral container eklendikten sonra pod silinene kadar API'den kaldırılamaz veya değiştirilemez (durumu `Terminated` olarak kalır).
* **Statik Pod Desteği:** Statik pod'lar (`Static Pods`) üzerinde geçici konteyner çalıştırılamaz.

---

## 4. Süreç Alanı (Process Namespace) Paylaşımı

Distroless imajlarla çalışırken, geçici konteyner içinden ana uygulamanın süreçlerini (processes) izleyebilmek için **Process Namespace Sharing** özelliğinin aktif olması gerekir.

Pod tanımında `shareProcessNamespace: true` yapılandırıldığında veya `kubectl debug` komutuna `--share-processes` eklendiğinde, geçici konteyner içinden aşağıdaki işlemler yapılabilir:

```bash
# Ephemeral container içinden ana container'ın process'lerini listeleme
ps aux

# Ana container'ın dosya sistemine süreç ID'si (PID) üzerinden erişme
ls -la /proc/<PID>/root/
```

---

## 5. Gerçek Dünya Teşhis Senaryoları

### Senaryo A: Distroless Go Uygulaması Yanıt Vermiyor (Dondu)

```bash
# 1. Pod içine netshoot enjekte et
kubectl debug -it frozen-api-pod --image=nicolaka/netshoot --target=go-app

# 2. Bağlantı durumlarını kontrol et
netshoot> ss -tulnp           # Açık TCP/UDP portları ve bağlantı durumları
netshoot> curl localhost:8080/health
netshoot> dig postgres-service # DNS çözümlemesi başarılı mı?

# 3. Süreç detayını oku
netshoot> cat /proc/1/status | grep State
```

### Senaryo B: DNS Çözümleme Hataları

```bash
# 1. Debug container'ını başlat
kubectl debug -it nginx-pod --image=busybox:1.36 --target=nginx

# 2. DNS ve resolv.conf kontrollerini yap
nslookup kubernetes.default
nslookup custom-api.production.svc.cluster.local
cat /etc/resolv.conf
```

---

## 6. Debug Yöntemlerinin Karşılaştırması

| Yöntem | Pod Durdurulur mu? | Konteyner İçi Araç Gerekir mi? | Canlı Durum Korunur mu? |
| :--- | :---: | :---: | :---: |
| **`kubectl exec`** | ❌ Hayır | ✅ Evet (sh/bash ve araçlar olmalı) | ✅ Evet |
| **Ephemeral Container** | ❌ Hayır | ❌ Hayır (Dışarıdan imaj bağlanır) | ✅ Evet |
| **Pod Kopyalama (`--copy-to`)** | ❌ Hayır | ❌ Hayır | ⚠️ Kısmen (Yeni pod kopyalanır) |
| **Podu Silip Yeniden Başlatma** | ✅ Evet | ❌ Hayır | ❌ Hayır (Tüm durum sıfırlanır) |

---

## Özet

Geçici konteynerler (**ephemeral containers**), özellikle sıkılaştırılmış ve distroless imajların kullanıldığı modern canlı (production) ortamlarda, uygulamaların çalışmasını kesintiye uğratmadan ve pod durumunu kaybetmeden sorun tespiti yapabilmek için vazgeçilmez bir araçtır.
