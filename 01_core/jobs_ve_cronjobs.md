# Jobs ve CronJobs: Tek Seferlik ve Zamanlanmış Görevler

Kubernetes'te Deployment veya DaemonSet gibi nesneler, içlerindeki uygulamaların **sonsuza kadar çalışmasını** bekler. Eğer uygulama işini bitirip sonlanırsa, Kubernetes bunu bir hata olarak algılar ve pod'u yeniden başlatır. 

Ancak bazı işlemler sadece tek bir görevi yerine getirip (örneğin veritabanı şeması güncellemek, veri analizi yapmak veya yedek almak) başarıyla sonlanmak üzere tasarlanmıştır. Bu tür iş yükleri için **Job** ve **CronJob** nesneleri kullanılır.

---

## 1. Job (Tek Seferlik Görevler)

Job, belirtilen sayıda pod'un başarıyla sonlanmasını (exit 0 ile bitmesini) garanti eden nesnedir.

### Temel Yapılandırma Parametreleri:
* **`completions`:** Job'ın tamamlanmış sayılması için kaç adet pod'un başarıyla bitmesi gerektiğini belirtir. Varsayılan değer 1'dir.
* **`parallelism`:** Aynı anda en fazla kaç pod'un çalışabileceğini sınırlar. Örneğin `completions: 10` ve `parallelism: 3` yaparsanız, işler üçer üçer paralel eritilir.
* **`backoffLimit`:** Eğer pod hata verip çökerse (`exit 1`), Kubernetes'in pes etmeden önce işi kaç kez yeniden deneyeceğini belirler. Varsayılan değer 6'dır.
* **`restartPolicy`:** Job pod'ları için bu değer ya `OnFailure` (hata durumunda aynı pod içinde konteyneri yeniden başlat) ya da `Never` (hata durumunda yeni pod oluştur) olmalıdır. `Always` kullanılamaz.

---

## 2. CronJob (Zamanlanmış Görevler)

CronJob, Linux dünyasındaki `cron` tablosunun Kubernetes versiyonudur. Belirli zaman dilimlerinde (takvime göre) otomatik olarak yeni bir **Job** tetikler.

### Zamanlama Formatı (Schedule Spec):
Zamanlama standart 5 haneli cron formatıyla belirtilir:
```text
# ┌───────────── dakika (0 - 59)
# │ ┌───────────── saat (0 - 23)
# │ │ ┌───────────── ayın günü (1 - 31)
# │ │ │ ┌───────────── ay (1 - 12)
# │ │ │ │ ┌───────────── haftanın günü (0 - 6) (Pazar=0 veya 7)
# │ │ │ │ │
# * * * * *
```
Örnek: `0 3 * * *` (Her gece saat 03:00'te tetiklenir).

### İleri Seviye Parametreler:
* **`concurrencyPolicy`:** Önceki zamanlamadan tetiklenen Job hala çalışırken yeni zamanlama saati gelirse ne yapılacağını belirler:
  * `Allow` (Varsayılan): İkisinin aynı anda çalışmasına izin ver.
  * `Forbid`: Önceki bitmeden yenisini başlatma (ikincisini atla).
  * `Replace`: Önceki çalışanı iptal et ve yeni gelenle değiştir.
* **`suspend`:** `true` olarak ayarlanırsa, CronJob'un gelecekteki tüm tetiklenmeleri geçici olarak askıya alınır.
* **`successfulJobsHistoryLimit` / `failedJobsHistoryLimit`:** Kubernetes'in geçmişte tamamlanmış/başarısız olmuş kaç adet Job geçmişini (pod logları dahil) saklayacağını sınırlar (çöplük oluşmasını engeller).

---

## 3. TTL Controller: Bitmiş İşlerin Otomatik Silinmesi

Job pod'ları tamamlandıktan sonra loglarının incelenebilmesi için kümede `Completed` statüsünde kalmaya devam eder. Ancak bu podlar temizlenmezse API Server üzerinde yük oluşturur.

**TTL (Time To Live) Controller** ile işi biten Job'ların otomatik olarak temizlenmesini sağlayabiliriz:

```yaml
spec:
  ttlSecondsAfterFinished: 3600 # İş bittikten 1 saat sonra Job ve bağlı podları otomatik sil
```

---

## 4. Örnek CronJob Yapılandırması

Aşağıda, her gün gece yarısı 00:00'da çalışan ve veritabanı yedeği alan örnek bir CronJob manifesti linklenmiştir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [jobs_ve_cronjobs_manifest_1.yaml](../Manifests/01_core/jobs_ve_cronjobs_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. En İyi Pratikler (Best Practices)

1. **Eşgüçlülük (Idempotency):** Ağ kesintileri veya controller gecikmeleri nedeniyle bir CronJob aynı zaman dilimi için nadiren de olsa iki kez tetiklenebilir. Bu yüzden çalıştırdığınız script veya program **idempotent** olmalıdır (örneğin yedek alınmışsa üzerine yazmalı veya hata vermeden geçmelidir).
2. **Kapanma Süresi (ActiveDeadlineSeconds):** Sonsuz döngüye giren veya ağda takılı kalan bir Job'ın kaynakları sonsuza dek tüketmesini engellemek için `activeDeadlineSeconds` limiti koyun. Bu süre aşılırsa Kubernetes işi zorla sonlandırır.
