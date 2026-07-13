# Sidecar ve Init Konteynerleri (Sidecar & Init Containers)

Kubernetes pod'ları birden fazla container barındırabilir. Bu container'ların rolleri pod içindeki görevlerine ve yaşam döngülerine göre üç gruba ayrılır: **Init Container** (başlangıç hazırlığı), **Sidecar Container** (yardımcı servis) ve **Uygulama Container'ı** (ana iş yükü).

---

## 1. Init Containers (Başlangıç Konteynerleri)

Init container'lar, ana uygulama container'ları **başlamadan önce** tamamlanmak üzere çalışan özel container'lardır. Sıralı (sequential) şekilde çalışırlar; yani her bir init container başarıyla tamamlanmadan bir sonraki init container veya ana uygulama container'ı başlamaz.

### Yaygın Kullanım Alanları

* **Hizmet Bağımlılığı Kontrolü:** Ana uygulamanın bağlanacağı veritabanı veya API servisinin hazır olmasını beklemek (`nslookup db-service`).
* **Yapılandırma Dosyası Oluşturma:** Uygulama ayarlarını bir Vault veya API üzerinden çekip ortak alana (`emptyDir` volume) yazmak.
* **İzinleri Düzenleme:** Docker imajındaki yetkilerin yetersiz olduğu durumlarda dosya sahipliğini (`chown`) veya okuma/yazma izinlerini (`chmod`) ayarlamak.
* **Veritabanı Göçü (Migration):** Uygulama ayağa kalkmadan önce veritabanı şemasını güncellemek.

### Init Container vs. Uygulama Container Farkları

| Özellik | Init Container | Uygulama Container |
| :--- | :--- | :--- |
| **Çalışma Sırası** | Sıralı (biri biter, diğeri başlar) | Paralel |
| **Başarısızlık Durumu** | Başarısız olursa pod `restartPolicy` kuralına göre baştan çalıştırılır | Liveness/Readiness probe'lara göre yeniden başlatılır |
| **Probe Desteği** | ❌ (Liveness, readiness ve startup probe desteklenmez) | ✅ (Tüm probe tipleri desteklenir) |
| **Kaynak Hesabı** | Init container'ların en yüksek isteği temel alınır | Tüm çalışan container'ların toplamı esas alınır |

---

## 2. Sidecar Containers (Native Sidecar - Kubernetes v1.29+)

Kubernetes v1.29 sürümüyle birlikte **Native Sidecar desteği** ekosisteme entegre edilmiştir. Sidecar'lar artık `initContainers` dizisi altında, ancak `restartPolicy: Always` niteliğiyle tanımlanmaktadır. Bu sayede, normal init container'ların aksine, pod'un tüm yaşam döngüsü boyunca **arkada çalışmaya devam ederler**.

### Neden Native Sidecar?

Eski Kubernetes sürümlerinde sidecar'lar normal `containers` altında tanımlanırdı. Bu durum, özellikle tek seferlik çalışan **Job** veya **CronJob** işlerinde büyük sorun yaratıyordu; çünkü ana iş yükü bittiğinde sidecar konteyner çalışmaya devam ettiği için pod `Completed` (Tamamlandı) durumuna geçemiyor ve takılı kalıyordu. Native sidecar ile bu sorun tamamen çözülmüştür.

### Sidecar Kullanım Senaryoları

| Senaryo | Sidecar Görevi | Popüler İmajlar |
| :--- | :--- | :--- |
| **Log Toplama** | Ana uygulamanın stdout/file loglarını toplayıp merkezi sunucuya iletmek | `fluentbit`, `promtail`, `filebeat` |
| **Proxy / mTLS** | Ağ trafiğini şifrelemek ve trafiği yönetmek (Service Mesh) | `envoy`, `istio-proxy` |
| **Metrik Toplama** | Uygulamaya ait performans verilerini Prometheus formatında sunmak | `prometheus/node-exporter` |
| **Yapılandırma Güncelleme** | Vault şifrelerini veya dinamik config dosyalarını yenilemek | `vault-agent`, `config-reloader` |

---

## 3. Üç Konteyner Türünün Karşılaştırması

| Özellik | Init Container | Sidecar Container (Native) | Uygulama Container |
| :--- | :--- | :--- | :--- |
| **Çalışma Süresi** | Uygulama başlamadan önce çalışır ve sonlanır | Pod açık olduğu sürece çalışmaya devam eder | Pod açık olduğu sürece çalışmaya devam eder |
| **Tanımlandığı Yer** | `spec.initContainers[]` | `spec.initContainers[]` + `restartPolicy: Always` | `spec.containers[]` |
| **Probe Desteği** | ❌ | ✅ | ✅ |
| **Ortak İletişim** | Ortak disk (`emptyDir`) üzerinden tek yönlü | Ortak disk ve `localhost` ağı üzerinden tam erişim | Ortak disk ve `localhost` ağı üzerinden tam erişim |
| **Job / CronJob Uyumu** | ✅ | ✅ (Ana iş bittiğinde otomatik sonlanır) | ❌ (Eski sidecar yönteminde sonlanmazdı) |

---

## 4. Kaynak Hesaplama Kuralları

Kubernetes, podun toplam kaynak talebini (Requests) ve sınırını (Limits) hesaplarken şu formülü kullanır:

```
Pod Toplam Kaynağı = max(Init İstekleri) + Σ(Uygulama Konteynerleri + Sidecar Konteynerleri) + Pod Overhead
```

> [!IMPORTANT]
> Sidecar konteynerler sürekli çalıştığı için kaynak hesaplamasında normal uygulama konteynerleriyle **toplanır**. Init konteynerler ise sadece başlangıçta çalıştığı için, aralarındaki en yüksek kaynak tüketen init konteynerin değeri ayrıca hesaba dahil edilir.

---

## 5. Native Sidecar ile Başlatma Sırası Garantisi

Native sidecar yapısı, bağımlı servislerin başlatma sırasını kesin olarak garanti eder:

```
initContainers (Sıralı Adımlar):
  1. wait-for-db (Init)        ──► Tamamlandı ve kapandı ✅
  2. vault-agent (Sidecar)     ──► Başlatıldı, "Ready" olana kadar bekleniyor...
     ▼ (Sidecar Hazır)
  3. main-app (Uygulama)       ──► Başlatılabilir (Artık DB ve şifreler hazır)
```

Eski yöntemde sidecar'lar normal container dizisinde yer aldığı için hangi konteynerin önce başlayacağı bilinemezdi ve bu durum uygulamanın çökerek `CrashLoopBackOff` durumuna düşmesine neden olabilirdi.

---

## 6. Örnek: Native Sidecar Tanımlı Job (YAML)

Aşağıdaki Job manifestosu, native sidecar özelliğini kullanarak bir log toplayıcı ile birlikte çalışır. Job asıl işini tamamladığında log toplayıcı da otomatik olarak sonlandırılır:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [sidecar_ve_init_konteynerleri_manifest_1.yaml](../Manifests/01_core/sidecar_ve_init_konteynerleri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## Özet

Çoklu konteyner mimarileri pod tasarımı yaparken esneklik kazandırır. **Init container'lar** ile hazırlık aşamalarını çözerken, Kubernetes v1.29+ ile gelen **native sidecar'lar** sayesinde loglama, proxy ve güvenlik gibi yan hizmetleri ana uygulamadan bağımsız ve güvenli bir şekilde yönetebiliriz.
