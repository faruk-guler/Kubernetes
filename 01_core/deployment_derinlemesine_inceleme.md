# Deployment ve ReplicaSet Kavramı

Bir önceki bölümde Pod'ların ölümlü olduğunu öğrendik. Donanımsal bir arıza çıktığında veya sunucu yeniden başlatıldığında, o sunucunun üzerindeki "çıplak" pod kaybolur ve kendi kendine ayağa kalkamaz.

İşte bu sorunu çözmek, podların sayısını sabit tutmak ve versiyon güncellemelerini sızıntısız yönetmek için Kubernetes'in kalbi olan **Deployment** nesnesini kullanırız.

## Ölçeklendirme (Scaling) ve Kendi Kendini İyileştirme (Self-healing)

Uygulamalarımızı doğrudan `Pod` nesnesi olarak değil, her zaman `Deployment` nesnesi olarak kümeye yükleriz.

Deployment, pod'ları doğrudan kendisi oluşturup yönetmez. Mimari olarak araya **ReplicaSet** (Kopya Kümesi) adında bir alt seviye nesne koyar:

```
Deployment (İstenen durum şablonu)
    ↳ ReplicaSet v1 (Sürüm yöneticisi)
          ↳ Pod-1 (Uygulama)
          ↳ Pod-2 (Uygulama)
          ↳ Pod-3 (Uygulama)
```

**Kendi Kendini İyileştirme:**
Deployment'a "Bana her zaman 3 adet kopya (replica) ver" dediğinizde, bu görev ReplicaSet'e iletilir. ReplicaSet, arkasına yaslanır ve kümeyi gözetler. Eğer sunuculardan biri alev alır ve `Pod-1` yok olursa, ReplicaSet saniyeler içinde yeni bir sunucuda yeni bir Pod oluşturarak sayıyı tekrar 3'e tamamlar.

**Ölçeklendirme:**
Trafik arttığında kopya sayısını artırmak için tek bir komut yeterlidir:

```bash
kubectl scale deployment/api-server --replicas=5
```

Bu sayede anında 2 yeni sunucu (pod) daha devreye alınır.

---

## Güncelleme Stratejileri (RollingUpdate vs Recreate)

Yazılım geliştirme sürecinin en sancılı anı, uygulamaya yeni bir özellik eklendiğinde bunu kesintisiz bir şekilde (zero-downtime) canlıya (production) almaktır. Deployment bu süreci otomatik yönetir. İki farklı stratejisi vardır:

### 1. RollingUpdate (Kademeli Güncelleme - Varsayılan)

Sıfır kesinti sağlamak için eski pod'ların kapatılıp yeni pod'ların açılmasını kademeli (taksit taksit) yapan stratejidir.

İki kritik parametresi vardır:

* **maxSurge:** Güncelleme sırasında hedeflenen sayının (örn: 3) en fazla kaç adet *üzerine çıkılabileceğini* belirler. (Geçici olarak 4 pod çalışmasına izin vermek).
* **maxUnavailable:** Güncelleme sırasında aynı anda en fazla kaç pod'un *devre dışı (offline) kalabileceğini* belirler.

**Akış (3 kopyalı bir sistemde):**

1. Yeni imajdan 1 adet yeni pod (v2) ayağa kalkar. Toplam pod sayısı 4 olur.
2. Yeni pod "Sağlıklı ve Hazır" sinyali verdiğinde, eski pod'lardan biri (v1) silinir.
3. Bu merdivenleme döngüsü (1 yeniyi aç, 1 eskiyi sil) tüm pod'lar v2 olana kadar kesintisiz devam eder.

### 2. Recreate (Yeniden Oluşturma)

Tüm eski pod'ların aynı anda acımasızca silinip, ardından yeni sürüm pod'ların başlatılmasıdır.

* Eski podlar silinip yenileri açılana kadar **kesinti (downtime)** yaşanır.
* *Neden kullanılır?* Eğer veritabanı şemasında büyük bir değişiklik varsa ve eski sürüm koda sahip pod ile yeni sürüm koda sahip pod'un aynı veritabanına bağlanması çakışma (veri bozulması) yaratacaksa, ikisinin aynı anda çalışmasını engellemek için `Recreate` kullanılır.

---

## Rollout ve Rollback Yönetimi

Deployment üzerinden yapılan güncellemeleri (Rollout) ve hatalı durumlarda eski sürüme geri dönmeyi (Rollback) yönetmek Kubernetes'in en güçlü özelliklerinden biridir.

Siz `api=ghcr.io/company/api:v2.0` imajıyla bir güncelleme başlattığınızda, Deployment eski ReplicaSet'i (v1.0) silmez! Onun içindeki pod sayısını 0'a indirir ve onu tarihçede (revision history) yedek olarak saklar. Yeni imaj için yeni bir ReplicaSet (v2.0) oluşturur.

```bash
# 1. Yeni sürümü (v2.0) başlatma
kubectl set image deployment/api-server api=ghcr.io/company/api:v2.0

# 2. Güncelleme sürecini canlı olarak izleme
kubectl rollout status deployment/api-server

# 3. Güncelleme geçmişini (Revizyonları) görüntüleme
kubectl rollout history deployment/api-server
```

### Rollback (Anında Geri Alma)

Diyelim ki v2.0 sürümünü yüklediniz ama yazılımcılar kodda hata yapmış, kullanıcılar sisteme giremiyor. Şirket içi panik başladı!

Hiç sorun değil, aşağıdaki tek satırlık komutla saniyeler içinde bir önceki sorunsuz sürüme dönebilirsiniz:

```bash
# Anında bir önceki sürüme geri dön (Rollback)
kubectl rollout undo deployment/api-server
```

Kubernetes, hata veren v2.0 ReplicaSet'in podlarını sıfıra indirirken, yedekte bekleyen v1.0 ReplicaSet'i tekrar 3 kopyaya çıkaracak ve sistem saniyeler içinde normale dönecektir.

---

### İleri Seviye (Production) Deployment Parametreleri

Manifesto (YAML) yazarken büyük şirketlerin her zaman kullandığı bazı hayat kurtarıcı parametreler:

* **`minReadySeconds`:** Yeni koda sahip bir pod `Ready` (Hazır) olduktan sonra, o pod'un gerçekten sağlıklı olduğuna ikna olmak için kaç saniye daha bekleyeceğinizi belirler. Örneğin 15 saniye. Eğer pod açılıp 10 saniye sonra bellek sızıntısından çöküyorsa, Deployment güncellemeyi (faciayı) diğer pod'lara yaymadan otomatik olarak durdurur.
* **`revisionHistoryLimit`:** Geriye dönük kaç adet eski ReplicaSet'in saklanacağını belirler (Varsayılan 10). Cluster'ın çöplüğe dönmemesi için genellikle 3 veya 5 yapılır.

Pod'larımızı ve onları yöneten Deployment'ları gördük. Peki veritabanları ne olacak? Veritabanları da aynı şekilde mi yönetiliyor?

Bir sonraki bölümde, Deployment'ın kardeşleri olan `StatefulSet`, `DaemonSet` ve `Job` kavramlarını inceleyeceğiz.
