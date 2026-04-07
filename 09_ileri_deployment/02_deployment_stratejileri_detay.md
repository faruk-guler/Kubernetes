# Uygulamalı Deployment Stratejileri

Kubernetes'te sadece `RollingUpdate` değil, iş ihtiyaçlarına göre `Blue-Green` ve `Canary` stratejilerini de **native** (yerleşik) objelerle yönetebiliriz.

---

## 2.1 Blue-Green Deployment

Yeni versiyonu (Green) tamamen ayağa kaldırıp, trafiği bir anda eski versiyondan (Blue) yeniye yönlendirme mantığıdır. Sıfır downtime ve anında geri dönüş (rollback) sağlar.

### Çalışma Mantığı:
1.  **Blue:** Mevcut versiyon çalışmaktadır (Label: `version=v1`).
2.  **Service:** Trafiği `version=v1` etiketli podlara yönlendirir.
3.  **Green:** Yeni versiyon ayağa kaldırılır (Label: `version=v2`).
4.  **Geçiş:** Servis içindeki `selector` güncellenerek trafiğin tamamı `v2`'ye aktarılır.

### Örnek YAML (Service Switch):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-svc
spec:
  selector:
    app: my-app
    version: v2  # Trafik anında v2'ye (Green) geçer
  ports:
  - port: 80
    targetPort: 8080
```

---

## 2.2 Canary Deployment

Yeni versiyonu önce küçük bir kullanıcı kitlesine (%10, %20 gibi) açıp, sorun yoksa kademeli olarak yayma mantığıdır.

### Native Yöntem (Replica Scaling):
Argo Rollouts veya bir Service Mesh (Istio) yoksa, Canary şu şekilde yapılır:
1.  Aynı `app: my-app` etiketine sahip iki farklı Deployment (V1 ve V2) oluşturulur.
2.  Servis, `app: my-app` üzerinden her iki deployment'ın podlarına da trafik gönderir.
3.  **Ağırlık Ayarı:** V1'den 9 pod, V2'den 1 pod çalıştırırsanız trafiğin yaklaşık %10'u Canary (V2) sürümüne gider.

### Doğrulama Komutu (yyy Nugget):
Trafiğin hangi podlara gittiğini terminalden test etmek için:
```bash
for i in $(seq 1 20); do 
  curl -s <APP_URL> | grep "version" 
done
```

---

## 2.3 Recreate Stratejisi

Eski podların tamamı kapatılır, ancak kapandıktan sonra yenileri açılır. Downtime (kesinti) kabul edilebilir durumlar veya aynı anda iki versiyonun çalışmasının veri tutarsızlığı (Örn: DB migration) yaratacağı senaryolarda kullanılır.

```yaml
spec:
  strategy:
    type: Recreate
```

---

## 2.4 Hangi Strateji Ne Zaman?

| Strateji | Kesinti | Risk | Maliyet | Senaryo |
|:---|:---:|:---:|:---:|:---|
| **RollingUpdate** | Yok | Orta | Düşük | Standart Web Uygulamaları |
| **Recreate** | Var | Düşük | Düşük | Veritabanı Değişiklikleri |
| **Blue-Green** | Yok | Düşük | Yüksek | Kritik, rollback gerektiren sistemler |
| **Canary** | Yok | En Düşük | Orta | Yeni özellik denemeleri |

---
*← [Ana Sayfa](../README.md)*
