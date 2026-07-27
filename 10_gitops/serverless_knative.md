# Knative ile Serverless Kubernetes Mimarisi

Bulut bilişim mimarisinde her uygulamanın ve mikroservisin 7 gün 24 saat boyunca kesintisiz çalışması gerekmez. Özellikle belirli aralıklarla tetiklenen işler, arka planda çalışan raporlama servisleri veya değişken trafik alan API'ler için kaynakların boşta bekletilmesi maliyet kaybıdır. **Knative**, Kubernetes üzerinde sunucusuz (**Serverless**) uygulama geliştirme standartlarını tanımlayan; sadece trafik geldiğinde çalışan, trafik olmadığında sıfıra inen (**Scale-to-Zero**) ve olay tabanlı (event-driven) çalışan bir altyapı motorudur.

---

## 1. Neden Kubernetes Üzerinde Serverless?

| Özellik | Geleneksel Deployment | Knative Serverless |
|:---|:---:|:---:|
| **Boşta Bekleme Maliyeti (Standby)** | Var (Pod'lar her zaman en az 1 replica çalışır). | ❌ Yok (İstek gelmediğinde 0'a iner, maliyet oluşturmaz). |
| **Otomatik Ölçekleme (Autoscaling)** | Yavaş (HPA CPU/RAM bazlı veya KEDA). | Çok Hızlı (Knative Pod Autoscaler - KPA, istek sayısına göre). |
| **Revizyon / Versiyon Yönetimi** | Manuel (Farklı deployment'lar). | ✅ Otomatik (Her kod/konfigürasyon değişikliğinde yeni revizyon). |
| **Trafik Bölüştürme (Traffic Splitting)** | Harici araçlar (Ingress/Istio). | ✅ Dahili (Servis tanımı içinden yüzdelik geçiş yapılır). |

---

## 2. Knative Kurulumu (Serving & Eventing)

Knative Serving (istek yönlendirme ve ölçekleme) ve Kourier ağ katmanını kurmak için:

```bash
KNATIVE_VERSION="v1.16.0"

# 1. Knative Serving CRD ve Çekirdek Bileşenlerini Kurun
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml

# 2. Hafif Ağ Katmanı (Kourier Ingress) Kurulumu
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml

# 3. Knative'e Kourier Ingress Kullanmasını Bildirin
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# 4. Kurulumları Doğrulayın
kubectl get pods -n knative-serving
```

---

## 3. Knative Service ile Sıfıra Ölçekleme (Scale-to-Zero)

Knative'de çalışan her uygulama bir `Service` (serving.knative.dev) nesnesi olarak tanımlanır. Bu nesne arkada otomatik olarak bir Route, Configuration ve Revision oluşturur.

### Örnek Knative Service Tanımı

Aşağıdaki tanım, 60 saniye boyunca hiç HTTP isteği almazsa pod sayısını otomatik olarak 0'a düşürecektir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [serverless_knative_manifest_1.yaml](../Manifests/09_gitops/serverless_knative_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Uygulamaya giden trafik kesildiğinde, Knative `activator` podu devreye girer, canlı podları kapatır ve gelen ilk isteği yakalayıp yeni pod ayağa kalkana kadar (cold-start) kuyrukta tutar.

---

## 4. Trafik Bölüştürme (Traffic Splitting)

Knative, bir servisin farklı revizyonları (versiyonları) arasında trafiği bölüştürmeyi çok kolaylaştırır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [serverless_knative_manifest_2.yaml](../Manifests/09_gitops/serverless_knative_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Knative Eventing (Olay Tabanlı Sunucusuz Mimari)

Knative, HTTP tabanlı Serving dışında, olay kaynaklarından (Kafka, RabbitMQ, GitHub webhook vb.) gelen mesajları dinleyerek uygulamaları tetikleyen **Knative Eventing** modülüne sahiptir. Bu sayede, kuyruğa yeni bir mesaj düştüğünde işleyici (worker) uygulamalar otomatik ayağa kalkıp mesajı işler ve kuyruk boşaldığında tekrar sıfıra kapanır.
*(Detaylı mimari ve örnekler için bkz: [knative_eventing.md](knative_eventing.md))*
