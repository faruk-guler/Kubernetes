# Ephemeral Containers (Geçici Debug Konteynerleri)

Ephemeral container'lar, **çalışan bir pod'a sonradan eklenen** ve yalnızca debug/sorun giderme amacıyla kullanılan geçici container'lardır. Kubernetes v1.25'ten itibaren **stable (GA)** durumdadır.

---

## Neden Gerekli?

Modern cloud-native uygulamalar genellikle **distroless** veya minimal imajlarla paketlenir. Bu imajlarda `bash`, `curl`, `dig`, `netstat` gibi araçlar bulunmaz. Sorun çıktığında:

- `kubectl exec` yetersiz kalır (araçlar yok)
- Pod'u yeniden başlatmak debug verisini yok eder
- Debug imajıyla yeni pod açmak durumu yeniden üretmez

**Ephemeral container**, çalışan pod'u durdurmadan içine araç kutusu enjekte eder.

---

## Kullanım

```bash
# Temel kullanım — netshoot ile ağ debug'u
kubectl debug -it <pod-adı> --image=nicolaka/netshoot --target=<ana-konteyner>

# Örnek: production-api pod'una bağlan
kubectl debug -it production-api-7d4f9b --image=nicolaka/netshoot --target=api

# BusyBox ile basit debug
kubectl debug -it <pod-adı> --image=busybox:1.36 --target=<konteyner>

# Pod'u kopyalayarak debug (orijinali bozmadan)
kubectl debug <pod-adı> -it --image=ubuntu --copy-to=debug-pod --share-processes
```

### Popüler Debug İmajları

| İmaj | Araçlar |
|---|---|
| `nicolaka/netshoot` | curl, dig, nmap, tcpdump, iperf, ss, netstat |
| `busybox:1.36` | sh, wget, nslookup, ping |
| `ubuntu:22.04` | apt ile her şey kurulabilir |
| `alpine:3.19` | apk ile hafif araçlar |
| `docker.io/library/python:3.12-slim` | Python debug scriptleri |

---

## Ephemeral Container Özellikleri ve Kısıtlamalar

| Özellik | Değer |
|---|---|
| Kaynak garantisi | ❌ Yok — requests/limits tanımlanamaz |
| Port tanımı | ❌ `ports`, `livenessProbe`, `readinessProbe` desteklenmez |
| Yeniden başlatma | ❌ Asla otomatik restart edilmez |
| Kalıcılık | ❌ Eklendikten sonra değiştirilemez veya kaldırılamaz |
| Static pod uyumu | ❌ Static pod'larda desteklenmez |
| Oluşturma yöntemi | `kubectl debug` veya API'nin `ephemeralcontainers` endpoint'i |

> [!WARNING]
> Ephemeral container eklendikten sonra `kubectl edit` ile değiştirilemez. Yanlış yapılandırıldıysa pod'u yeniden başlatmak gerekir.

---

## Process Namespace Paylaşımı

Distroless container'lardaki process'leri görmek için **process namespace sharing** aktif edilmelidir:

```yaml
# Pod spec'ine ekleyin
spec:
  shareProcessNamespace: true
  containers:
  - name: app
    image: gcr.io/distroless/python3
```

Bu ayarla ephemeral container, ana container'ın process'lerini görebilir:

```bash
# Ephemeral container içinden ana container process'lerini listele
ps aux

# Belirli bir process'in dosya sistemi görünümü
ls -la /proc/<PID>/root/
```

---

## Gerçek Dünya Senaryosu

### Senaryo: Distroless Go Uygulaması Dondu

```bash
# 1. Ephemeral container ekle
kubectl debug -it frozen-api-pod \
  --image=nicolaka/netshoot \
  --target=go-app

# 2. Debug container içinde ağ durumunu kontrol et
netshoot> ss -tulnp          # açık portlar
netshoot> curl localhost:8080/health
netshoot> dig postgres-svc   # DNS çözümlemesi

# 3. Process durumunu incele
netshoot> cat /proc/1/status | grep State
```

### Senaryo: DNS Sorunu

```bash
kubectl debug -it <pod-adı> --image=busybox:1.36 --target=<konteyner>

# DNS çözümleme testi
nslookup kubernetes.default
nslookup my-service.production.svc.cluster.local
cat /etc/resolv.conf
```

---

## Ephemeral Container vs Diğer Debug Yöntemleri

| Yöntem | Pod Durdurma | Araç Gereksinimi | Durum Koruma |
|---|---|---|---|
| `kubectl exec` | ❌ | Pod içinde araç olmalı | ✅ |
| Ephemeral Container | ❌ | Dış imaj kullanılır | ✅ |
| Pod kopyalama (`--copy-to`) | ❌ | Dış imaj kullanılır | ⚠️ Kopya durum |
| Pod silip yeniden başlatma | ✅ | — | ❌ Durum kaybolur |

> [!TIP]
> **En iyi pratik:** Production'da daima ephemeral container kullanın. Pod'u yeniden başlatmak debug için son çare olmalıdır.

---
