# Uygulama Dağıtım Stratejileri (Deployment Strategies)

Kubernetes üzerinde koşan uygulamalarınızın yeni sürümlerini (updates) yayına alırken tercih ettiğiniz yöntem; sistemin kesinti süresini (downtime), kaynak tüketim maliyetini ve olası bir hata anında geri alma (rollback) risk profilinizi doğrudan belirler. Kubernetes ve ekosistem araçları bu geçişleri yönetmek için farklı dağıtım stratejileri sunar.

---

## 1. Dağıtım Stratejilerine Genel Bakış

```
RollingUpdate   ──► Kademeli güncelleme (Varsayılan). Sıfır kesinti, düşük risk.
Recreate        ──► Önce eskileri sil, sonra yenileri başlat. Kısa kesinti, basit geçiş.
Blue/Green      ──► İki paralel ortam, anlık trafik yönlendirme. Sıfır kesinti, hızlı rollback.
Canary          ──► Trafiğin küçük bir kısmını (%10) yeni sürüme gönder, test et. En güvenli.
```

---

## 2. RollingUpdate (Kademeli Güncelleme - Varsayılan)

Kubernetes'in varsayılan stratejisidir. Eski sürüm podlar birer birer silinirken, yerlerine yeni sürüm podlar adım adım ayağa kaldırılır.

### Örnek Yapılandırma

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [dagitim_stratejileri_manifest_1.yaml](../Manifests/09_gitops/dagitim_stratejileri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Güncelleme İzleme ve Geri Alma Komutları

```bash
# 1. Güncelleme sürecini canlı takip edin:
kubectl rollout status deployment/billing-api -n production

# 2. Sürüm geçmişini (revizyon listesini) görüntüleyin:
kubectl rollout history deployment/billing-api -n production

# 3. Hata anında en son kararlı sürüme geri dönün:
kubectl rollout undo deployment/billing-api -n production

# 4. Belirli bir geçmiş revizyona (Örn: revizyon 2) doğrudan geri dönün:
kubectl rollout undo deployment/billing-api --to-revision=2 -n production
```

---

## 3. Recreate (Yeniden Oluşturma)

Bu stratejide, API sunucusu önce çalışan tüm eski podları kapatıp siler, ardından yeni sürüm podları başlatır. Eski sürüm tamamen silinip yenisi başlayana kadar **kısa bir kesinti (downtime)** yaşanır.

### Örnek Yapılandırma

```yaml
spec:
  replicas: 3
  strategy:
    type: Recreate
```

### Hangi Durumlarda Kullanılır?

* **Database Migration:** İki farklı sürümün (Örn: v1 ve v2) aynı anda veritabanıyla konuşmasının şemayı bozacağı kritik durumlarda.
* **RWO Volume Kullanımı:** Konteynerin sadece tek bir düğüme yazabildiği (`ReadWriteOnce`) disk bağımlılıklarında.

---

## 4. Blue/Green (Mavi/Yeşil) Dağıtım

Blue/Green stratejisinde, eski sürüm (Blue) canlıda çalışırken, yeni sürüm (Green) tamamen ayrı bir Deployment olarak ayağa kaldırılır. Green ortamı test edilip tamamen hazır olduğunda, Kubernetes Servis (Service) seçicisi (selector) güncellenerek trafik anında Green'e aktarılır.

```
[Kullanıcı Trafiği] ──► [ Kubernetes Service ]
                               │
                ┌──────────────┴──────────────┐
         (Trafik Aktif)                (Trafik Yok)
                ▼                             ▼
       [ Mavi Deployment ]            [ Yeşil Deployment ]
          (Eski Sürüm)                   (Yeni Sürüm)
```

### Servis Yönlendirme ve Geri Alma Yönetimi

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [dagitim_stratejileri_manifest_2.yaml](../Manifests/09_gitops/dagitim_stratejileri_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

```bash
# 1. Yeşil (Green) ortam hazır olduğunda trafiği anlık aktarın:
kubectl patch service api-service -n production \
  -p '{"spec":{"selector":{"version":"green"}}}'

# 2. Hata anında trafiği anında eski kararlı (Blue) ortama geri çekin:
kubectl patch service api-service -n production \
  -p '{"spec":{"selector":{"version":"blue"}}}'

# 3. Güncelleme tamamen onaylandıktan sonra eski (Blue) deployment'ı silin:
kubectl delete deployment api-blue -n production
```

---

## 5. Canary (Kanarya) Dağıtım

Yeni sürümün (Canary) küçük bir pod kopyası oluşturulur ve ortak servis etiketleri sayesinde trafiğin sadece küçük bir kısmı (%10-%20) yeni sürüme yönlendirilir. Gerçek kullanıcı trafiğiyle izlenen Canary podlarında hata yoksa, kademeli olarak stable sürümün kopyaları azaltılıp canary artırılır.

### A. Stable Deployment (Stabil - Eski Sürüm)

```yaml
# api-stable.yaml
spec:
  replicas: 9 # %90 Trafik
  template:
    metadata:
      labels:
        app: my-service
        version: stable
```

### B. Canary Deployment (Yeni Sürüm)

```yaml
# api-canary.yaml
spec:
  replicas: 1 # %10 Trafik (Toplam 10 pod içinde 1 adet)
  template:
    metadata:
      labels:
        app: my-service
        version: canary
```

### Kademeli Trafik Geçiş Komutları

```bash
# Canary stabil çalışıyorsa, kopyaları eşitle (%50 / %50):
kubectl scale deployment api-canary --replicas=5
kubectl scale deployment api-stable --replicas=5

# Tam geçiş başarılı olduysa, canary'i 10 yapın ve eski sürümü silin:
kubectl scale deployment api-canary --replicas=10
kubectl delete deployment api-stable
```

---

## 6. Argo Rollouts ile Gelişmiş Dağıtım

Manuel canary veya blue/green geçişlerini otomatikleştirmek, Prometheus metriklerine bakarak hata oranı yükseldiğinde otomatik rollback (kendi kendine geri alma) yapmak için Kubernetes yerleşik Deployment nesnesi yerine **Argo Rollouts** CRD'leri kullanılır.
*(Detaylar ve örnek yapılandırmalar için bkz: [argo_rollouts.md](argo_rollouts.md))*

---

## 7. Strateji Seçim Kılavuzu

| Senaryo Gereksinimi | Önerilen Strateji | Kesinti Süresi | Ekstra Kaynak Maliyeti |
|:---|:---:|:---:|:---:|
| Standart web servisleri (Genel) | **RollingUpdate** | 🟢 Sıfır | 🟡 Düşük (%25 ek kaynak) |
| Veritabanı şema güncellemesi (DB Migration) | **Recreate** | 🔴 Var | 🟢 Sıfır |
| Hızlı rollback gerektiren yüksek riskli servisler | **Blue/Green** | 🟢 Sıfır | 🔴 Yüksek (%100 ek kaynak) |
| Gerçek kullanıcı testi gereken riskli yayınlar | **Canary** | 🟢 Sıfır | 🟡 Düşük |
| Tam otomatik, metrik analizli (SRE standardı) | **Argo Rollouts** | 🟢 Sıfır | 🟡 Düşük |
