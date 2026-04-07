# İleri Pod Teknikleri ve Konteyner Tipleri

Bu bölüm, standart Pod yapısının ötesine geçerek Kubernetes'in sunduğu özel konteyner tiplerini ve gelişmiş çalışma modellerini kapsamaktadır.

---

## 1. Init Containers (Hazırlık Konteynerleri)

**Init Container'lar**, pod içerisindeki ana uygulama konteyneri ayağa kalkmadan önce çalışan özel konteynerlerdir. Genellikle yapılandırma dosyalarını hazırlamak, veritabanı bağlantısını beklemek veya gerekli scriptleri çalıştırmak için kullanılırlar.

### Temel Özellikler:
- **Sıralı Çalışma:** Birden fazla init container varsa, bunlar tanımlandıkları sırayla çalışır. Biri bitmeden diğeri başlamaz.
- **Tamamlanma Zorunluluğu:** Bir init container başarıyla (`exit 0`) tamamlanmadan ana konteyner asla başlamaz.
- **Probe Desteği Yok:** Init container'lar için `liveness`, `readiness` veya `startup` probe tanımlanamaz.

```yaml
spec:
  initContainers:
  - name: install
    image: busybox:1.36
    command: ['sh', '-c', 'echo "Hazırlık yapılıyor..." && sleep 5']
  containers:
  - name: my-app
    image: my-app:v1
```

---

## 2. Sidecar Containers (Yardımcı Konteynerler)

Sidecar'lar, ana uygulama ile aynı Pod içinde çalışarak ona destekleyici hizmetler (log toplama, proxy, güvenlik) sağlar. 

> [!IMPORTANT]
> **Native Sidecar Desteği (K8s 1.29+):** Artık sidecar konteynerleri `initContainers` içine eklenerek `restartPolicy: Always` ile tanımlanır. Bu sayede ana uygulama bitene kadar yaşamaya devam ederler ancak ana uygulama başlamadan önce hazır hale gelirler.

```yaml
spec:
  initContainers:
  - name: log-exporter
    image: fluent-bit:3.0
    restartPolicy: Always    # <--- Bu konteyner bir Sidecar'dır
  containers:
  - name: main-app
    image: my-app:v1
```

---

## 3. Ephemeral Containers (Geçici Konteynerler)

Ephemeral container'lar, çalışan bir Pod'un içine **çalışma anında (runtime)** eklenen, genellikle hata ayıklama (troubleshooting) için kullanılan geçici konteynerlerdir.

### Neden Gerekli?
- **Distroless İmajlar:** Shell veya paket yöneticisi içermeyen güvenli imajlarda `kubectl exec` çalışmaz. Bu durumda dışarıdan bir `debug` konteynerini Pod'a enjekte etmek gerekir.
- **İnteraktif Hata Ayıklama:** Çalışan Pod'un network veya dosya sistemini canlı incelemek için kullanılır.

```bash
# Çalışan bir pod'a debug konteyneri ekle
kubectl debug -it <pod-adi> --image=busybox --target=<konteyner-adi>
```

---

## 4. Static Pods

Static Pod'lar, API Server tarafından değil, doğrudan ilgili node üzerindeki **Kubelet** tarafından yönetilen pod'lardır.

### Özellikleri:
- **Konum:** Genellikle `/etc/kubernetes/manifests` dizini altındaki YAML dosyalarından okunur.
- **Kullanım:** Kubernetes'in kendi bileşenleri (etcd, scheduler, api-server) genellikle static pod olarak çalışır.
- **Mirror Object:** API Server'da sadece `read-only` bir kopyası görünür; `kubectl delete` ile silinemezler (dosyanın silinmesi gerekir).

---

## 5. Konteyner Tipleri Karşılaştırması

| Özellik | Init Container | Sidecar (Native) | App Container | Ephemeral |
|:---|:---:|:---:|:---:|:---:|
| **Başlama Sırası** | En Önce | Init'ten sonra | En son | Manuel (İstekle) |
| **Bitiş Zamanı** | Başarıyla bitmeli | Uygulama bitince | Uygulama bitince | Manuel / Geçici |
| **Probe Desteği** | Hayır | Evet | Evet | Hayır |
| **RestartPolicy** | Sadece Default | Always | Always/Never | Yok |

---
*← [Pod ve Objeler](04_pod_ve_objeler.md) | [Ana Sayfa](../README.md)*
