# Deployment Deep Dive

Kubernetes'te tek bir pod çalıştırdığımızda (çıplak pod), donanımsal bir arıza veya node çökmesi durumunda o podun kaybolduğunu ve kendi kendine ayağa kalkamadığını öğrenmiştik. Bu sorunu çözmek için pod kopyalarını (replica) yöneten ve pod sayısını sabit tutan `ReplicaSet` nesnesi mevcuttur. Ancak, production ortamlarında uygulamalarımızı neredeyse hiç doğrudan `ReplicaSet` ile deploy etmeyiz.

Uygulamalarımızı güncellememiz gerektiğinde (örneğin yeni bir imaj versiyonu çıktığında) sıfır kesinti (zero-downtime) sağlamak ve bir şeyler ters gittiğinde anında eski sürüme geri dönebilmek (rollback) isteriz. İşte bu yaşam döngüsü yönetimini gerçekleştiren en temel ve en popüler Kubernetes objesi **Deployment**'tır.

---

## Deployment $\rightarrow$ ReplicaSet $\rightarrow$ Pod İlişkisi

Deployment, pod'ları doğrudan kendisi oluşturup yönetmez. Bunun yerine bir alt seviye nesne olan **ReplicaSet**'leri yönetir. Mimari zincir şu şekilde çalışır:

```
Deployment (İstenen durum şablonu)
    │
    ├── ReplicaSet v1 (Eski sürüm — 0 replikaya düşürüldü)
    └── ReplicaSet v2 (Yeni sürüm — 3 replika) ← Aktif
              ├── Pod-1 (v2)
              ├── Pod-2 (v2)
              └── Pod-3 (v2)
```

Siz Deployment üzerinde bir güncelleme yaptığınızda (örneğin imaj sürümünü değiştirdiğinizde), Deployment yeni sürüm için sıfırdan yeni bir ReplicaSet (v2) oluşturur. Eski ReplicaSet (v1) tamamen silinmez; kopyaları sıfıra indirilir ama geçmişte (revision history) saklanır. Bu sayede geri dönmek istediğinizde anında eski ReplicaSet scale edilerek rollback tamamlanır.

---

## Tam Bir Deployment Anatomisi

Aşağıda, tüm production-ready parametreleri barındıran örnek bir Deployment manifestosu yer almaktadır:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: production
  labels:
    app: api-server
    version: v2.1.0
spec:
  replicas: 3
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: api-server
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  minReadySeconds: 15
  progressDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app: api-server
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: api
        image: ghcr.io/company/api:v2.1.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
        readinessProbe:
          httpGet:
            path: /readyz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 5"]
      terminationGracePeriodSeconds: 30
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: api-server
```

---

## Kritik Parametrelerin Açıklamaları

* **replicas:** Cluster'da sürekli olarak kaç adet sağlıklı pod kopyasının çalışacağını belirtir.
* **revisionHistoryLimit:** Rollback (geri alma) işlemleri için geçmişte en fazla kaç adet eski ReplicaSet saklanacağını belirtir. Bu sınırın aşılması eski ReplicaSet'lerin silinmesine yol açar.
* **minReadySeconds:** Bir podun "Running" olduktan sonra gerçekten "Available" (erişilebilir) kabul edilmesi için en az kaç saniye sağlıklı (ready) kalması gerektiğini belirtir. Bu parametre, başlangıçta çalışıp 5-10 saniye sonra çöken (crash loop) pod'ların tespit edilip güncellemenin otomatik olarak durdurulması için hayati önem taşır.
* **progressDeadlineSeconds:** Güncelleme işleminin en fazla kaç saniye sürmesine izin verileceğini belirtir. Belirtilen sürede güncelleme tamamlanamazsa Deployment durdurulmaz veya otomatik rollback yapılmaz; sadece controller, Deployment durum koşullarını (conditions) `Progressing: False` ve `Reason: ProgressDeadlineExceeded` olarak günceller ve bir Event oluşturur.

---

## Güncelleme Stratejileri

### 1. RollingUpdate (Kademeli Güncelleme)

Sıfır kesinti (zero-downtime) ile yeni versiyona geçmek için pod'ların kademeli olarak güncellenmesi yöntemidir. Burada iki kritik parametre güncellenme hızını ve güvenliğini belirler:

* **maxSurge:** Güncelleme sırasında hedeflenen replika sayısının en fazla kaç adet üzerine çıkılabileceğini belirtir. Yüzde (%) veya sayısal değer alabilir. `maxSurge: 1` ise, 3 replikalı sistemde güncelleme anında geçici olarak 4 pod çalışabilir.
* **maxUnavailable:** Güncelleme sırasında aynı anda en fazla kaç pod'un devre dışı (offline) kalabileceğini belirtir. `maxUnavailable: 1` ise, 3 replikalı sistemde en az 2 pod'un her zaman aktif çalışması garanti edilir.

#### Kademeli Güncelleme Akışı (maxSurge=1, maxUnavailable=1)

1.  **Başlangıç:** 3 adet eski pod çalışmaktadır `[v1][v1][v1]`.
2.  **Adım 1 (Surge):** Yeni sürümden 1 adet pod oluşturulur `[v1][v1][v1] + [v2]`. Toplam pod sayısı 4 olur (maxSurge limitine ulaşılır).
3.  **Adım 2 (Scale Down):** Eski sürümden 1 pod silinir `[v1][v1][v2]`. Toplam pod sayısı 3'e düşer.
4.  **Adım 3 (İlerleme):** Yeni pod `readinessProbe`'u geçip hazır hale geldikten sonra eski pod'lar sırayla kapatılmaya ve yenileri açılmaya devam eder: `[v1][v2][v2]` $\rightarrow$ `[v2][v2][v2]`.

### 2. Recreate (Yeniden Oluşturma)

Tüm eski pod'ların aynı anda silinip, ardından yeni sürüm pod'ların başlatılması yöntemidir.

```yaml
strategy:
  type: Recreate
```

* **Akış:** `[v1][v1][v1]` $\rightarrow$ `[]` $\rightarrow$ `[v2][v2][v2]`
* **Risk:** Eski pod'lar silinip yenileri açılana kadar geçen sürede **servis kesintisi (downtime)** yaşanır.
* **Kullanım Amacı:** Aynı anda iki farklı versiyonun (v1 ve v2) aynı veritabanına erişmesinin çakışma yaratacağı durumlarda veya tekil bir lisans/bağlantı kısıtı olan servislerde tercih edilir.

---

## Rollout Yönetim Komutları

Deployment üzerinde yapılan güncellemeleri yönetmek için aşağıdaki `kubectl` komutları kullanılır:

```bash
# 1. Container imajını güncelleyerek yeni sürümü başlatma
kubectl set image deployment/api-server api=ghcr.io/company/api:v2.2.0 -n production

# 2. Güncelleme sürecini canlı olarak izleme
kubectl rollout status deployment/api-server -n production

# 3. Güncelleme geçmişini (revisions) görüntüleme
kubectl rollout history deployment/api-server -n production

# 4. Rollout geçmişine güncelleme nedeni ekleme (Önerilen yöntem)
kubectl annotate deployment/api-server kubernetes.io/change-cause="v2.2.0: Ödeme entegrasyonu eklendi" -n production

# 5. Bir önceki sürüme anında geri dönme (Rollback)
kubectl rollout undo deployment/api-server -n production

# 6. Belirli bir geçmiş revizyona geri dönme (Örn: Revizyon 2)
kubectl rollout undo deployment/api-server --to-revision=2 -n production

# 7. Güncellemeyi geçici duraklatma (Canary testleri için kullanışlıdır)
kubectl rollout pause deployment/api-server -n production

# 8. Duraklatılan güncellemeyi devam ettirme
kubectl rollout resume deployment/api-server -n production

# 9. Pod'ları imaj değiştirmeden sırayla yeniden başlatma (ConfigMap değişikliklerinde kullanılır)
kubectl rollout restart deployment/api-server -n production
```

---

## Sorun Giderme (Troubleshooting)

Eğer yeni bir güncelleme başlattıysanız ve rollout tamamlanmıyorsa:

1.  **Deployment Durumu:** `kubectl describe deployment api-server -n production` komutunu çalıştırın ve `Conditions` altındaki `Progressing` durumunu inceleyin. `Reason: ProgressDeadlineExceeded` yazıyorsa belirlenen sürede pod'lar hazır olamamıştır.
2.  **ReplicaSet İnceleme:** `kubectl get rs -n production` ile yeni sürüm ReplicaSet'in (DESIRED, CURRENT, READY kolonlarını) durumunu görün. DESIRED 3 iken READY 0 ise pod'lar hata alıyordur.
3.  **Pod Logları:** `kubectl get pods -n production` ile hata veren pod adını bulup `kubectl logs <pod-adi> --previous` ile container çökmeden önceki log kayıtlarını inceleyin.

---

## Prometheus ile Deployment Metrikleri

```promql
# İstenen replika sayısı ile hazır olan replika sayısı eşit mi kontrolü
kube_deployment_spec_replicas{deployment="api-server"} - 
kube_deployment_status_replicas_available{deployment="api-server"} > 0

# Deployment'ın genel erişilebilirlik durumu
kube_deployment_status_condition{condition="Available", status="False"}
```
