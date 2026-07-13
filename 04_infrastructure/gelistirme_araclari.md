# Inner Loop ve Geliştirici Araçları (Development Tools)

Yazılım geliştirme dünyasında **"Inner Loop" (İç Geliştirme Döngüsü)**, kod editörünüzde bir değişiklik yaptığınız an ile o değişikliğin sonuçlarını çalışan test ortamında canlı gördüğünüz an arasındaki süredir.

Kubernetes ortamlarında bu döngü varsayılan olarak oldukça hantaldır: Kodu yaz ──► Docker imajı derle ──► Registry'ye gönder (push) ──► Deployment manifestosunu güncelle ──► Pod'un yeniden başlamasını ve hazır olmasını bekle. Bu hantal süreç, geliştiricilerin üretkenliğini düşürür.

Bu bölümde, bu süreci saniyelere indiren, lokal makineniz ile uzak Kubernetes kümesi arasında adeta gizli bir tünel ve sıcak yükleme (hot-reload) hattı kuran 4 popüler geliştirici aracını inceliyoruz: **Telepresence**, **Skaffold**, **Tilt** ve **DevSpace**.

---

## 1. Araç Seçim Matrisi

| Araç | Temel Görevi | Güçlü Olduğu Durum |
|:---|:---|:---|
| **Telepresence** | Küme trafiğini lokale yönlendirir | Cluster bağımlılığı olan (örneğin DB) servisleri lokalde debug etmek için. |
| **Skaffold** | Kod değiştikçe otomatik imaj derler ve deploy eder | CI/CD süreçlerinin yerel simülasyonu için. |
| **Tilt** | Görsel dashboard ile çoklu servis yönetimi sağlar | Birbirine bağımlı çok sayıda mikroservisi aynı anda geliştirirken. |
| **DevSpace** | Konteyner içine canlı dosya senkronizasyonu yapar | Pod'u yeniden başlatmadan konteyner içi canlı geliştirme için. |

---

## 2. Telepresence — Küme Trafiğini Lokale Yönlendirme

Telepresence, Kubernetes kümesindeki bir servise giden trafiği lokal bilgisayarınızda koşturduğunuz sürece (IDEs/Debugger) yönlendirir. Böylece uygulamanız sanki küme içindeymiş gibi diğer Kubernetes servisleriyle doğrudan konuşabilir.

```bash
# 1. Kurulum (macOS)
brew install datawire/blackbird/telepresence

# 2. Kubernetes kümesine bağlantı kurun
telepresence connect

# 3. Artık küme içi DNS adreslerine yerel makinenizden erişebilirsiniz!
curl http://postgres-service.production.svc.cluster.local:5432

# 4. Kümedeki 'api-service' trafiğini lokal 8080 portunuza yönlendirin (Intercept)
telepresence intercept api-service \
  --namespace production \
  --port 8080:8080 \
  --env-file .env.intercept # Servise ait Environment değişkenlerini yerele indirir

# 5. Artık yerel debugger'ınızı 8080 portunda başlatıp canlı trafiği yakalayabilirsiniz!
go run main.go

# 6. Yönlendirmeyi (Intercept) sonlandırın
telepresence leave api-service-production

# 7. Bağlantıyı tamamen kapatın
telepresence quit
```

### Kişisel Yönlendirme (Personal Intercept)

Sadece sizin göndereceğiniz istekleri lokale yönlendirip, diğer kullanıcıların canlı sistemi kullanmaya devam etmesini sağlayabilirsiniz:

```bash
telepresence intercept api-service --port 8080 --http-header x-debug-user=kullanici_adim
```

---

## 3. Skaffold — Dosya Değişimlerini İzleyip Otomatik Dağıtma

Skaffold, yerel dosya sisteminizdeki kod değişikliklerini izler. Kod değiştiği anda imajı yeniden derler, etiketler ve kümeye (K3d, Minikube veya uzak küme) dağıtır.

### Örnek `skaffold.yaml` Yapılandırması

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gelistirme_araclari_manifest_1.yaml](../Manifests/04_infrastructure/gelistirme_araclari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Kullanım Komutları

```bash
# Geliştirme modu: Kod değiştikçe otomatik build, push ve deploy yapar, logları ekrana basar
skaffold dev

# Tek seferlik build ve deploy işlemi
skaffold run

# Kümedeki tüm dağıtılan kaynakları temizleme
skaffold delete
```

---

## 4. Tilt — Görsel Dashboard ile Çoklu Mikroservis Geliştirme

Tilt, karmaşık mikroservis projelerinde servislerin durumlarını ve loglarını takip edebileceğiniz interaktif bir tarayıcı arayüzü sunar. Projenin yapılandırılması Python benzeri bir dil olan **Tiltfile** ile yapılır.

### Örnek `Tiltfile` İçeriği

```python
# API İmajını derle ve kod değiştikçe hot-reload (canlı senkronizasyon) yap
docker_build('registry.example.com/api-service', './api',
  live_update=[
    sync('./api/src', '/app/src'), # Değişen kodları konteyner içine doğrudan senkronize et
  ])

# Kubernetes manifestlerini tanımla
k8s_yaml('./k8s/api-deployment.yaml')

# Servisi dışarı aç ve bağımlılıklarını belirle
k8s_resource('api-service',
  port_forwards='8080:8080',
  resource_deps=['database']) # Önce database kaynağı hazır olmalı

# Database manifestini yükle
k8s_yaml('./k8s/db-deployment.yaml')
k8s_resource('database', port_forwards='5432:5432')
```

### Komutlar

```bash
# Tilt Dashboard arayüzünü açarak projeyi başlatın (http://localhost:10350)
tilt up

# Tüm servisleri durdurup temizleyin
tilt down
```

---

## 5. DevSpace — Konteyner İçi Sıcak Yükleme (Hot-Reload)

DevSpace, pod'u veya konteyneri baştan başlatmadan, yerel dosya sisteminizde kaydettiğiniz dosyaları saniyeler içinde pod içindeki dosya sistemiyle senkronize eder.

```bash
# 1. Projeyi DevSpace ile başlatın (interaktif konfigürasyon hazırlar)
devspace init

# 2. Geliştirme modunu başlatın
# (Konteyner içinde shell açar, yerel dosya değişikliklerini anlık senkronize eder)
devspace dev

# 3. Tüm kaynakları kümeden temizleyin
devspace purge
```

---

## Özet

Kubernetes üzerinde geliştirme yaparken geleneksel build-push-deploy süreçleri zaman kaybına yol açar. **Skaffold** veya **Tilt** kullanarak imaj derlemelerini otomatize edebilir, **DevSpace** ile imaj derleme aşamalarını tamamen atlayıp konteyner içi kod senkronizasyonu yapabilir ve **Telepresence** ile uzak kümedeki trafiği doğrudan bilgisayarınıza tünelleyebilirsiniz.
