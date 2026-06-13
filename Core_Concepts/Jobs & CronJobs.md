# Jobs & CronJobs

Deployment ve StatefulSet sürekli çalışan iş yükleri içindir. **Job**, belirli bir görevi tamamlayıp çıkan iş yükleri için; **CronJob** ise bu görevleri zamanlanmış biçimde tekrarlayan yapı için tasarlanmıştır.

---

## Job — Tek Seferlik Görev

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  namespace: production
spec:
  # Kaç kez başarıyla tamamlanmalı?
  completions: 1          # Varsayılan: 1

  # Aynı anda kaç pod paralel çalışabilir?
  parallelism: 1          # Varsayılan: 1

  # Toplam kaç saniyede bitmeli? (0 = sınırsız)
  activeDeadlineSeconds: 600   # 10 dakika

  # Başarısızlıkta kaç kez tekrar dene?
  backoffLimit: 3

  # Job tamamlandıktan kaç saniye sonra silinsin?
  ttlSecondsAfterFinished: 3600   # 1 saat

  template:
    spec:
      restartPolicy: OnFailure    # Job'da Never veya OnFailure kullanılır
      containers:
      - name: migration
        image: ghcr.io/company/migrator:v1.2.0
        command: ["python", "manage.py", "migrate"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "1Gi"
```

```bash
# Job durumu
kubectl get job db-migration -n production
# NAME           COMPLETIONS   DURATION   AGE
# db-migration   1/1           45s        2m

# Job pod'u
kubectl get pods -l job-name=db-migration -n production

# Logları oku
kubectl logs job/db-migration -n production

# Başarısız pod'un logları
kubectl logs -l job-name=db-migration --previous -n production
```

---

## Paralel Job Desenleri

### Desen 1: Fixed Completion Count

```yaml
# 10 görevi 3 pod paralel işlesin
spec:
  completions: 10     # Toplam 10 başarılı tamamlama
  parallelism: 3      # Aynı anda 3 pod çalışır
  # Akış: 3 pod → bitince yeni 3 → ... → 10. tamamlandığında Job biter
```

### Desen 2: Work Queue (İş Kuyruğu)

```yaml
# completions belirtme — pod'lar kuyruktan kendi işini alır
spec:
  parallelism: 5
  # completions: yok → her pod kuyruğu kontrol eder,
  #                     boşsa çıkar, bir pod başarıyla bitince Job tamamlanır
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

### Desen 3: Indexed Job (Her Pod Farklı Görev)

```yaml
spec:
  completions: 100        # 100 farklı görev
  parallelism: 10         # Aynı anda 10 pod
  completionMode: Indexed # Her pod benzersiz index alır (0-99)
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
        - --total-shards=100
```

---

## CronJob — Zamanlanmış Görev

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-report
  namespace: production
spec:
  # Cron sözdizimi: dakika saat gün-ay ay gün-hafta
  schedule: "0 2 * * *"        # Her gece 02:00
  # schedule: "*/15 * * * *"   # Her 15 dakika
  # schedule: "0 9 * * 1-5"    # Hafta içi 09:00

  # Önceki çalışma bitmeden yeni başlamasın
  concurrencyPolicy: Forbid     # Allow | Forbid | Replace

  # Zamanında başlatılamazsa kaç saniye tolerans?
  startingDeadlineSeconds: 300  # 5 dakika geç kalırsa atla

  # Başarılı Job geçmişini kaç tane sakla?
  successfulJobsHistoryLimit: 3

  # Başarısız Job geçmişini kaç tane sakla?
  failedJobsHistoryLimit: 3

  # CronJob'u geçici durdur
  suspend: false

  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 3600
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: report-sa
          containers:
          - name: reporter
            image: ghcr.io/company/reporter:v2.1
            command: ["python", "generate_report.py"]
            resources:
              requests:
                cpu: "200m"
                memory: "256Mi"
              limits:
                cpu: "1"
                memory: "512Mi"
```

---

## ConcurrencyPolicy Detayı

| Politika | Davranış | Kullanım |
|:---------|:---------|:---------|
| `Allow` | Paralel çalışmaya izin ver | Bağımsız görevler |
| `Forbid` | Önceki bitmeden yeni başlatma | Kritik tek çalışma |
| `Replace` | Öncekini sil, yenisini başlat | Deadline'ı olan görevler |

---

## CronJob Yönetimi

```bash
# CronJob listesi
kubectl get cronjob -n production

# Son çalışmaları gör
kubectl describe cronjob daily-report -n production

# Manuel tetikleme (test için)
kubectl create job --from=cronjob/daily-report manual-run-$(date +%s) -n production

# CronJob'u durdur
kubectl patch cronjob daily-report -p '{"spec":{"suspend":true}}' -n production

# Devam ettir
kubectl patch cronjob daily-report -p '{"spec":{"suspend":false}}' -n production

# Job geçmişi
kubectl get jobs -n production --sort-by='.status.startTime'
```

---

## İpuçları ve Anti-Pattern'ler

```yaml
# ✅ Her zaman resource limits tanımla
# ✅ ttlSecondsAfterFinished kullan — eski pod'lar birikmesin
# ✅ restartPolicy: OnFailure (crash'te yeniden dene)
#    veya Never (debug için, pod silinmez)

# ❌ CronJob'da concurrencyPolicy: Allow + uzun çalışma
#    → Her dakika yeni pod açılır, cluster'ı boğar

# ✅ Idempotent görevler yaz
#    Aynı Job iki kez çalışsa da sonuç aynı olmalı
#    (DB migration'larda "already applied" kontrolü yap)

# ✅ Monitoring: CronJob başarısız olduğunda alert
```

```promql
# Prometheus: Başarısız Job alarmı
increase(kube_job_failed[1h]) > 0

# Son CronJob çalışması ne zaman?
kube_cronjob_next_schedule_time - time()

# CronJob hiç çalışmamış mı? (stuck detection)
time() - kube_cronjob_status_last_schedule_time > 3600
```

---

## Gerçek Dünya Kullanımları

| Kullanım | Schedule | Notlar |
|:---------|:---------|:-------|
| DB backup | `0 1 * * *` | Gece 01:00 |
| Cache temizleme | `0 */6 * * *` | 6 saatte bir |
| Rapor üretimi | `0 8 * * 1` | Pazartesi sabahı |
| Expired session temizlik | `*/30 * * * *` | 30 dakikada bir |
| ML model yeniden eğitim | `0 0 * * 0` | Haftada bir, Pazar |
| SSL sertifika kontrolü | `0 9 * * *` | Günlük kontrol |
