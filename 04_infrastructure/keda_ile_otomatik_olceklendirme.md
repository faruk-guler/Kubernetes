# KEDA ile Olay Güdümlü Otomatik Ölçeklendirme (KEDA Autoscaling)

**KEDA (Kubernetes Event-Driven Autoscaling)**, geleneksel Kubernetes HPA (Horizontal Pod Autoscaler) yapısının sadece CPU ve Bellek metriklerine bağımlı olan sınırlarını aşarak, podları harici olay kaynaklarına (events) göre ölçeklendiren CNCF Graduated statüsünde bir operatördür.

KEDA; Kafka, RabbitMQ, AWS SQS, Prometheus sorguları, Redis, PostgreSQL gibi 60'tan fazla dış sisteme bağlanarak, kuyruktaki mesaj sayısına veya gelen istek hızına göre uygulamalarınızı ölçeklendirebilir.

---

## 1. KEDA vs. Standart HPA

| Özellik | Standart HPA | KEDA (HPA Genişleticisi) |
|:---|:---|:---|
| **Metrik Kaynakları** | Sadece CPU, Bellek veya Özel Metrikler (Custom Metrics) | 60+ dış kaynak (Kafka, RabbitMQ, SQS, Prometheus vb.) |
| **Sıfıra Ölçekleme (Scale to 0)**| ❌ Yapamaz (En az 1 pod çalışmak zorundadır) | ✅ Yapabilir (Olay yoksa pod sayısını 0'a çekerek kaynak tasarrufu sağlar) |
| **Mekanizma** | Metrics Server üzerinden sorgular | KEDA Operator, ilgili dış kaynağı doğrudan izler ve HPA'yı besler |

---

## 2. KEDA Kurulumu (Helm)

KEDA bileşenlerini kümenize kurmak için:

```bash
# 1. KEDA Helm deposunu ekleyin
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# 2. KEDA'yı prometheus metrik sunucu desteğiyle kurun
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set prometheus.metricServer.enabled=true \
  --set prometheus.operator.enabled=true
```

---

## 3. RabbitMQ Kuyruk Uzunluğuna Göre Ölçeklendirme (Örnek)

Bir RabbitMQ kuyruğunda biriken mesaj sayısına (Queue Length) göre çalışan worker (tüketici) podlarımızı ölçeklendirmek istiyoruz. Bağlantı bilgilerinin güvenliği için **TriggerAuthentication** ve **ScaledObject** tanımlarını kullanacağız.

### Adım 1: Bağlantı Bilgisi İçin Secret Oluşturun

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [keda_ile_otomatik_olceklendirme_manifest_1.yaml](../Manifests/04_infrastructure/keda_ile_otomatik_olceklendirme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Adım 2: KEDA Tetikleyici Kimlik Doğrulaması (TriggerAuthentication)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [keda_ile_otomatik_olceklendirme_manifest_2.yaml](../Manifests/04_infrastructure/keda_ile_otomatik_olceklendirme_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Adım 3: ScaledObject Tanımı

Bu tanım, KEDA'ya hangi uygulamayı, hangi şartlarda ölçeklendirmesi gerektiğini söyler:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [keda_ile_otomatik_olceklendirme_manifest_3.yaml](../Manifests/04_infrastructure/keda_ile_otomatik_olceklendirme_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Kafka Topic Lag Değerine Göre Ölçeklendirme

Kafka consumer grubundaki okunmamış mesaj gecikmesine (**topic lag**) göre ölçekleme:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [keda_ile_otomatik_olceklendirme_manifest_4.yaml](../Manifests/04_infrastructure/keda_ile_otomatik_olceklendirme_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Cron (Zaman) Bazlı Ölçeklendirme

İş yüklerinizin belirli gün ve saatlerde yoğunlaşacağını önceden biliyorsanız (Örn: İş başlama saatleri, kampanya günleri) Cron tetikleyicisi kullanabilirsiniz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [keda_ile_otomatik_olceklendirme_manifest_5.yaml](../Manifests/04_infrastructure/keda_ile_otomatik_olceklendirme_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. KEDA ScaledObject İzleme ve Durum Kontrolleri

```bash
# 1. ScaledObject durumlarını listeleyin
kubectl get scaledobject -n production
# Çıktıda READY ve ACTIVE durumları 'True' olmalıdır.
# ACTIVE=True, tetikleyicide mesaj/olay tespit edildiğini ve podların ayağa kalktığını gösterir.

# 2. Arka planda oluşturulan HPA nesnesini kontrol edin
kubectl get hpa -n production

# 3. KEDA operatörünün loglarını inceleyin
kubectl logs -n keda -l app=keda-operator --tail=50
```

---

## Özet

KEDA, olay güdümlü mimarilerde bulut kaynak tüketimini optimize etmenin en güçlü yoludur. Dış kaynaklardaki yüke anlık cevap verebilmesi ve sıfıra ölçekleme (**`minReplicaCount: 0`**) yeteneği sayesinde, geceleri veya pasif saatlerde çalışmayan worker podlarınızı kapatarak altyapı maliyetlerinizde **%60-80 oranında tasarruf** sağlayabilir.
