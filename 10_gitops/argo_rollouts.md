# Argo Rollouts ile Gelişmiş Dağıtım Yöntemleri

Kubernetes'in yerleşik `Deployment` nesnesi, kademeli güncelleme (RollingUpdate) sırasında hata oranlarını denetleyemez veya otomatik geri alma (rollback) kararlarını metrik analizlerine göre veremez. **Argo Rollouts**, Kubernetes'e gelişmiş **Canary, Blue/Green ve A/B Testing** yetenekleri ekleyen, **Prometheus, Grafana Loki, Datadog** gibi izleme araçlarından aldığı metrikleri analiz ederek hatalı sürümleri otomatik olarak geri çeken (auto-abort) gelişmiş bir dağıtım denetleyicisidir.

---

## 1. Kurulum Adımları

Argo Rollouts denetleyicisini ve komut satırı eklentisini (CLI Plugin) kurmak için:

```bash
# 1. Helm ile Denetleyici Kurulumu
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace \
  --set dashboard.enabled=true \
  --set notifications.enabled=true

# 2. Kubectl Plugin (Krew yardımıyla) Kurulumu:
kubectl krew install argo-rollouts
kubectl argo rollouts version
```

---

## 2. Standart Deployment Nesnesini Rollout'a Dönüştürme

Mevcut bir Deployment'ı Rollout yapısına geçirmek için `apiVersion` ve `kind` alanlarını güncellemeniz ve strateji adımlarını tanımlamanız yeterlidir.

### Örnek `Rollout` Yapılandırması (`billing-rollout.yaml`)

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argo_rollouts_manifest_1.yaml](../Manifests/09_gitops/argo_rollouts_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Dönüşüm sonrasında eski deployment'ın replica sayısını sıfırlayıp yönetimi Rollout'a devredin:

```bash
kubectl scale deployment billing-service --replicas=0 -n production
```

---

## 3. Experiment (Deney) ile Paralel Sürüm Karşılaştırması

Argo Rollouts'un en güçlü özelliklerinden biri, iki farklı sürümü (örneğin v2.0-stable ve v3.0-canary) gerçek kullanıcı trafiğinin küçük bir yüzdesinde karşılaştırıp hangisinin daha hızlı ve hatasız çalıştığını test etmeyi sağlayan **Experiment** kaynağıdır.

### Örnek `Experiment` Tanımı

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argo_rollouts_manifest_2.yaml](../Manifests/09_gitops/argo_rollouts_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Çoklu Analiz Kaynağı (AnalysisTemplate)

Sürümün doğruluğunu test ederken tek bir kaynağa bağlı kalmak yerine, hem Prometheus'tan hata oranını çekebilir hem de Datadog veya Cloudwatch üzerindeki servis durumlarını aynı anda doğrulayabilirsiniz.

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argo_rollouts_manifest_3.yaml](../Manifests/09_gitops/argo_rollouts_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Pre/Post Promotion (Geçiş Öncesi ve Sonrası) Analizleri

Özellikle Blue/Green dağıtımlarda, trafiği yeni ortama (Green) aktarmadan hemen önce (**Pre-Promotion**) entegrasyon testlerini çalıştırmak ve geçiş bittikten hemen sonra (**Post-Promotion**) performans analizlerini devreye almak için adım yapılandırmaları kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argo_rollouts_manifest_4.yaml](../Manifests/09_gitops/argo_rollouts_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Slack Bildirimleri (Notifications)

Rollout süreçlerindeki durum değişikliklerini (Örn: pause durumuna geçme, hata algılama ve rollback durumları) anlık olarak Slack kanalınıza iletmek için bildirimler kurgulanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argo_rollouts_manifest_5.yaml](../Manifests/09_gitops/argo_rollouts_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. ArgoCD Entegrasyonu

ArgoCD, Argo Rollouts nesnelerini yerel olarak tanır. Rollout güncellendiğinde, tüm adımlar başarıyla geçilip analizler olumlu sonuçlanana kadar ArgoCD uygulamayı "Progressing (İlerliyor)" durumunda gösterir. Rollout bittiğinde durum "Healthy (Sağlıklı)" olur.

---

## 8. Rollout CLI Yönetim ve Hata Ayıklama Komutları

```bash
# 1. Tüm aktif rollout durumlarını izleyin (Dinamik dashboard arayüzü)
kubectl argo rollouts get rollout billing-service -n production --watch

# 2. Manuel duraklatılmış (paused) bir rollout'u bir sonraki adıma geçirin (Promote)
kubectl argo rollouts promote billing-service -n production

# 3. Kademeli adımları es geçip doğrudan %100 yükleme yapın
kubectl argo rollouts promote billing-service -n production --full

# 4. Acil bir durumda güncellemeyi iptal edin ve anında kararlı sürüme geri dönün (Abort/Rollback)
kubectl argo rollouts abort billing-service -n production
kubectl argo rollouts undo billing-service -n production

# 5. Görsel web arayüzünü (Dashboard) yerel bilgisayarınızda başlatın
kubectl argo rollouts dashboard -n production
# Tarayıcıda http://localhost:3100 adresini açın
```
