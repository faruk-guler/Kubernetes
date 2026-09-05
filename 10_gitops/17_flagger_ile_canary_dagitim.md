# Flagger ile Otomatik Metrik Analizli Canary Dağıtımları

Klasik yazılım dağıtımlarında (RollingUpdate) yeni bir sürüm çıktığınızda, podlar teker teker yenilenir. Ancak yeni sürümde bir bellek sızıntısı veya 500 hatası üreten bir yazılım hatası varsa, RollingUpdate bunu fark edemez; tüm podları günceller ve üretim ortamını kesintiye uğratır.

**Flagger**, CNCF mezuniyet yolundaki bir progressive delivery (aşamalı teslimat) operatörüdür. Yeni bir sürüm deploy edildiğinde trafiği kademeli olarak (%5, %10, %20...) yeni sürüme aktarır; her adımda Prometheus veya VictoriaMetrics metriklerini (Hata oranı, P99 yanıt süresi) sorgular. Bir anormallik sezerse **dağıtımı otomatik olarak durdurur ve anında eski sürüme geri alır (Auto-Rollback)**.

---

## 1. Argo Rollouts vs. Flagger

| Karşılaştırma Kriteri | Argo Rollouts | Flagger |
| :--- | :--- | :--- |
| **Doğal Ekosistem** | ArgoCD ekosistemi | **Flux v2**, Istio, Linkerd ekosistemi |
| **Kubernetes Nesnesi** | Kendi özel `Rollout` CRD'sini zorunlu tutar. | **Standart `Deployment`** nesnesiyle çalışır (Hiçbir şeyi değiştirmeniz gerekmez). |
| **Trafik Yönlendiriciler** | ALB, NGINX, Istio | **Istio, Linkerd, NGINX, Contour, Gateway API, Gloo** |
| **Geri Alma (Rollback)** | Analiz şablonları ile | Dahili Prometheus / MetricsQL kontrolleriyle |

> **En Büyük Avantajı:** Flagger kullanmak için mevcut Kubernetes `Deployment` ve `HPA` dosyalarınızı baştan yazmanıza gerek yoktur. Flagger, mevcut Deployment'ınızın yanına bir `Canary` CRD nesnesi bağlayarak çalışır.

---

## 2. Flagger Mimarisi Nasıl Çalışır?

Flagger bir `Canary` tanımı gördüğünde sahne arkasında şu akıllı adımları atar:

1. Asıl `app-deployment`'ınızı klonlayarak bir `app-deployment-primary` oluşturur (Kararlı sürüm).
2. Orijinal deployment'ı ise yeni gelen versiyonları test etmek için "Canary" olarak kullanır.
3. Önlerine Ingress veya Service Mesh (Istio / Linkerd / Gateway API) trafik yönlendiricisini koyar.
4. Geliştirici imajı güncellediğinde:
   - Canary podları ayağa kalkar.
   - Trafiğin %5'i Canary'ye yönlendirilir.
   - 1 dakika boyunca Prometheus'tan "HTTP başarı oranı %99'un üzerinde mi?" kontrol edilir.
   - Eğer metrikler sağlıklıysa trafik %10, %20, %30... şeklinde artırılır.
   - Maksimum eşiğe (Örn: %50) ulaşıldığında yeni sürüm artık `primary` yapılır ve trafik %100 olur.
   - **Eğer herhangi bir anda hata oranı %1'i aşarsa:** Trafik o saniye %0'a çekilir, Canary podları kapatılır ve Slack'e acil durum uyarısı gönderilir.

```text
       [ İstemci Trafiği ]
               │
               ▼
       ┌───────────────┐
       │ Traffic Split │ (Service Mesh / Gateway API)
       └───┬───────┬───┘
   (%90)   │       │   (%10)
           ▼       ▼
     ┌─────────┐ ┌─────────┐
     │ Primary │ │ Canary  │
     │  (v1)   │ │  (v2)   │
     └─────────┘ └────┬────┘
                      │
                      ▼
             ┌─────────────────┐
             │ Prometheus / VM │ ──► (Metrik Doğrulama)
             └────────┬────────┘
                      │
                      ▼
             ┌─────────────────┐
             │ Flagger Control │ ──► Başarılıysa İlerlet / Hatalıysa Geri Al!
             └─────────────────┘
```

---

## 3. Flagger Kurulumu

Flagger'ı kullandığınız ağ altyapısına (örneğin Linkerd, Istio veya NGINX) göre kurabilirsiniz:

```bash
# Helm deposunu ekleyin
helm repo add flagger https://flagger.app
helm repo update

# Flagger'ı Linkerd veya Istio entegrasyonuyla kurun
helm upgrade --install flagger flagger/flagger \
  --namespace flagger-system \
  --create-namespace \
  --set metricsServer=http://prometheus.monitoring:9090 \
  --set meshProvider=linkerd # Veya istio, nginx, gateway-api
```

---

## 4. `Canary` Nesnesi ile Otomatik Dağıtım Tanımı

Aşağıda, bir mikroservis için otomatik P99 gecikme ve %99 başarı oranı kontrolü yapan örnek bir `Canary` manifestosu yer almaktadır:

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: payment-service
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-service
  service:
    port: 8080
    targetPort: 8080
  # Aşamalı Dağıtım ve Metrik Analiz Kuralları
  analysis:
    interval: 1m      # Her kontrol arasındaki bekleme süresi
    threshold: 5      # 5 kez üst üste başarısızlıkta otomatik geri alma (rollback)
    maxWeight: 50     # Trafik en fazla %50'ye kadar yeni sürüme kaydırılsın
    stepWeight: 10    # Her başarılı adımda trafiği %10 artır
    metrics:
      - name: request-success-rate
        thresholdRange:
          min: 99     # Başarı oranı en az %99 olmalıdır
      - name: request-duration
        thresholdRange:
          max: 500    # P99 yanıt süresi 500ms altında kalmalıdır
```

---

## 5. Yük Testi Webhook Entegrasyonu (Load Testing)

Gece 03:00'te yeni bir versiyon çıktığınızda sistemde gerçek kullanıcı trafiği olmayabilir. Trafik yoksa hata oranını nasıl ölçeceksiniz?

Flagger, Canary dağıtımı başladığı anda otomatik olarak **K6**, **Hey** veya **JMeter** konteynerlerini tetikleyen `webhooks` desteği sunar. Yeni pod ayağa kalktığı anda yapay yük testi başlatılır, pod test edilir ve metrikler sağlıklıysa sürüm üretime geçirilir.

## Özet

**Flagger**, SRE mühendislerinin deployment yaparken ekran başında ter dökme devrini kapatır. Kodunuzu commit edin, arkanıza yaslanın; eğer bir hata varsa Flagger bunu insan gözünden çok daha hızlı tespit edip milisaniyeler içinde eski sürüme dönecektir.
