# Jobs & CronJobs

Şu ana kadar gördüğümüz tüm Kubernetes objeleri (Pod, Deployment, StatefulSet vb.), biz müdahale edip kapatmadığımız sürece sürekli çalışmaya devam etmesi gereken uzun ömürlü uygulamalarla ilgiliydi. Fakat her uygulama bu şekilde 7/24 çalışmak üzere tasarlanmamıştır. Sadece belirli bir işi yapmak üzere tetiklenen, işini bitirdikten sonra da düzgünce kapanması (exit 0) gereken birçok iş yükü mevcuttur.

---

## Neden Job ve CronJob?

Bu tarz "çalış ve dur" (run-to-completion) tipi uygulamaları eğer `Deployment` veya çıplak `Pod` (single pod) gibi objelerle çalıştırmaya kalkarsak bazı sorunlarla karşılaşırız:

* **Çıplak Pod Problemi:** Uygulamayı tek bir pod olarak deploy edersek, işini başarıyla tamamladığında durur ve sıkıntı olmaz. Ancak uygulama çalışırken çökerse (crash), çıplak pod bunu algılayıp kendini yeniden başlatmaz. Görev yarım kalır.
* **Deployment Problemi:** Eğer çökme ihtimaline karşı `Deployment` kullanırsak, bu sefer de uygulama işini başarıyla bitirip kapandığı an, Deployment bunu bir "hata" veya "kesinti" olarak algılar ve container'ı durmaksızın yeniden başlatır. Uygulama sonsuz bir döngüde aynı işi tekrar tekrar yapmaya başlar.

İşte bu sorunu çözmek için Kubernetes bizlere **Job** objesini sunmaktadır. Job, bir veya daha fazla pod oluşturur ve belirtilen sayıda pod başarıyla sonlanana kadar onları yönetir. Görev başarıyla tamamlandığında pod'ları durdurur ancak logları inceleyebilmemiz için pod'ları silmeden "Completed" durumunda bekletir.

---

## Job — Tek Seferlik Görev

Aşağıdaki örnekte, matematiksel olarak Pi sayısının ilk 2000 basamağını hesaplayıp kapanan klasik bir Job manifestosu yer almaktadır:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi-calculation
  namespace: production
spec:
  # Kaç adet başarılı pod tamamlanmalı?
  completions: 10         # Varsayılan: 1

  # Aynı anda kaç pod paralel çalışabilir?
  parallelism: 2          # Varsayılan: 1

  # Toplam kaç saniyede bitmeli? (0 = sınırsız)
  activeDeadlineSeconds: 100

  # Başarısızlıkta kaç kez tekrar dene?
  backoffLimit: 5

  # Job tamamlandıktan kaç saniye sonra otomatik silinsin?
  ttlSecondsAfterFinished: 3600

  template:
    spec:
      # Job için restartPolicy sadece Never veya OnFailure olabilir
      restartPolicy: Never
      containers:
      - name: pi
        image: perl:5.34
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
```

### Spec Parametrelerinin Detayları

* **completions:** Bu Job'un başarıyla tamamlanmış kabul edilmesi için toplamda kaç adet pod'un başarıyla (exit 0) sonlanması gerektiğini belirtir. Bu örnekte 10 pod'un da başarılı olması gerekir.
* **parallelism:** İşin hızlandırılması için aynı anda en fazla kaç pod'un paralel olarak çalışabileceğini belirtir. Burada `2` pod aynı anda çalışmaya başlar, biri bittikçe toplam sayı 10 olana kadar yeni pod'lar sıraya alınır.
* **backoffLimit:** Pod'lar hata aldığında (exit code 1 vb.) Kubernetes'in vazgeçmeden önce en fazla kaç kez yeni pod oluşturmayı deneyeceğini belirtir. Limit aşılırsa tüm Job "Failed" olarak işaretlenir.
* **activeDeadlineSeconds:** Job'un tamamlanması için izin verilen maksimum süredir. Süre aşılırsa çalışan tüm pod'lar durdurulur ve Job başarısız kabul edilir.
* **ttlSecondsAfterFinished:** Job tamamlandıktan sonra cluster'da gereksiz kaynak birikmesini önlemek için otomatik silinme süresidir (TTL Controller).

---

## Paralel Job Desenleri

### Desen 1: Sabit Tamamlama Sayısı (Fixed Completion Count)

Yukarıdaki Pi örneğinde olduğu gibi, belirli sayıda işin sırayla veya paralel olarak yapılması gereken senaryolardır. `completions` ve `parallelism` değerleri birlikte ayarlanır.

### Desen 2: İş Kuyruğu (Work Queue)

Kuyruktaki işleri tüketmek için kullanılan yapıdır. `completions` değeri belirtilmez. Pod'lar bağımsız olarak RabbitMQ veya AWS SQS gibi bir kuyruktan iş çeker. Kuyruk boşaldığında pod'lar başarıyla kapanır ve Job tamamlanır.

```yaml
spec:
  parallelism: 5
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: ghcr.io/company/worker:v1
        env:
        - name: QUEUE_URL
          value: "amqp://rabbitmq:5672/tasks"
```

### Desen 3: İndeksli Job (Indexed Job)

Her pod'un birbirinden farklı bir iş parçasını (shard) işlemesi gereken durumlarda kullanılır. `completionMode: Indexed` yapıldığında her pod'a `0` ile `completions-1` arasında benzersiz bir index atanır.

```yaml
spec:
  completions: 100
  parallelism: 10
  completionMode: Indexed
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: processor
        image: ghcr.io/company/processor:v1
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        command:
        - python
        - process.py
        - --shard=$(JOB_COMPLETION_INDEX)
```

---

## CronJob — Zamanlanmış Görev

**CronJob**, Linux dünyasındaki `crontab` yapısının Kubernetes halidir. Belirli bir zaman planına (schedule) göre periyodik olarak otomatik Job'lar oluşturur.

> [!NOTE]
> `CronJob` API'si Kubernetes 1.21 sürümüne kadar `batch/v1beta1` altındaydı. Ancak modern Kubernetes sürümlerinde artık tamamen kararlı (stable) olan `batch/v1` API grubu kullanılmaktadır.

Aşağıda her dakika başında çalışıp ekrana tarih yazan örnek bir CronJob yer almaktadır:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello-cron
  namespace: production
spec:
  # Standart Cron Sözdizimi: dakika saat gün-ay ay gün-hafta
  schedule: "*/1 * * * *"

  # Önceki çalışma tamamlanmadan yenisi tetiklenirse ne yapılmalı?
  concurrencyPolicy: Forbid

  # Zamanında tetiklenemezse kaç saniye tolerans tanınmalı?
  startingDeadlineSeconds: 300

  # Geçmişte tutulacak başarılı ve başarısız Job limitleri
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3

  # CronJob'u geçici olarak devre dışı bırakma (durdurma)
  suspend: false

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: hello
            image: busybox:1.36
            command:
            - /bin/sh
            - -c
            - date; echo Hello from the Kubernetes cluster
```

---

## ConcurrencyPolicy Detayı

| Politika | Davranış | Kullanım |
| :--- | :--- | :--- |
| `Allow` | Paralel çalışmaya izin ver | Birbirini etkilemeyen bağımsız işler |
| `Forbid` | Önceki bitmeden yeni Job başlatma | Veritabanı yedeği, çakışma riski olan işler |
| `Replace` | Önceki çalışan Job'u sil, yenisini başlat | Her zaman sadece en güncel veriyi isteyen işler |

---

## Job & CronJob Yönetimi

```bash
# Job ve CronJob durumlarını sorgulama
kubectl get jobs,cronjobs -n production

# Detaylı çalışma geçmişi ve log inceleme
kubectl describe cronjob hello-cron -n production
kubectl logs job/pi-calculation -n production

# Test amacıyla bir CronJob'u hemen (manuel) tetikleme
kubectl create job --from=cronjob/hello-cron manual-run-test -n production

# Bir CronJob'u geçici olarak durdurma (suspend) ve geri açma
kubectl patch cronjob hello-cron -p '{"spec":{"suspend":true}}' -n production
kubectl patch cronjob hello-cron -p '{"spec":{"suspend":false}}' -n production
```

---

## En İyi Pratikler ve İzleme

* **Resource Limits:** Job pod'ları kontrolsüz çalışıp cluster kaynaklarını tüketmesin diye her zaman `resources.limits` tanımlayın.
* **TTL Controller:** Eski tamamlanmış Job'ların otomatik temizlenmesi için `ttlSecondsAfterFinished` özelliğini aktif edin.
* **Idempotency (Eşgüçlülük):** Özellikle CronJob'larda pod'lar ağ kesintisi veya hata nedeniyle birden fazla kez tetiklenebilir. Uygulamanızın aynı işi mükerrer yapması durumunda hata vermeyecek şekilde tasarlanmış (idempotent) olması çok önemlidir (örneğin DB migration scriptlerinde "IF NOT EXISTS" kullanımı).

### Prometheus Alarm Metrikleri

```promql
# Son 1 saatte başarısız olan Job tespiti
increase(kube_job_failed[1h]) > 0

# CronJob'un uzun süredir tetiklenmediğini (stuck) tespit etme
time() - kube_cronjob_status_last_schedule_time > 3600
```
