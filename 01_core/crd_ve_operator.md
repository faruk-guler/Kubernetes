# CRD ve Operator Örüntüsü (CRD & Operator Pattern)

Kubernetes API, varsayılan olarak yalnızca Pod, Deployment, Service, ConfigMap gibi genel amaçlı kaynakları tanır. Ancak gerçek dünyada, "PostgreSQL Cluster", "Kafka Topic" veya "Yapay Zeka Modeli" gibi etki alanına özel (domain-specific) karmaşık kaynakları yönetmemiz gerekir.

**Custom Resource Definition (CRD)** ve **Operator** örüntüsü, Kubernetes'i kendi özel kaynaklarımızla genişleterek akıllı otomasyon sistemleri kurmamızı sağlar.

---

## 1. Neden CRD ve Operator?

Geleneksel yaklaşımlar ile Operator örüntüsü arasındaki temel fark şudur:

* **Standart Yaklaşım (Manuel/Script):** Kubernetes üzerinde bir PostgreSQL veritabanı kurmak için YAML dosyalarını uygularsınız. Yedek almak için cron scriptleri yazar, sunucu çöktüğünde veritabanı replikasyonunu elle düzeltirsiniz.
* **Operator Yaklaşımı (Akıllı Otomasyon):** Kubernetes'e *"Bana 3 düğümlü bir PostgreSQL kümesi aç"* talimatı verirsiniz (`kubectl apply`). Operator arka planda PostgreSQL'i kurar, yedeklemeleri otomatik alır ve bir düğüm çöktüğünde lider düğüm atamasını (failover) insan müdahalesi olmadan otomatik gerçekleştirir.

---

## 2. Custom Resource Definition (CRD)

CRD, Kubernetes API'sini genişleterek yeni bir nesne tipi (Custom Resource - CR) tanımlamamızı sağlar.

### Örnek CRD Tanımı (YAML)

Aşağıdaki CRD, Kubernetes API'sine `Database` adında yeni bir nesne tanımlar:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [crd_ve_operator_manifest_1.yaml](../Manifests/01_core/crd_ve_operator_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu CRD sisteme yüklendikten sonra artık doğrudan `kubectl` ile kendi veritabanı nesnemizi oluşturabiliriz:

```yaml
apiVersion: company.com/v1alpha1
kind: Database
metadata:
  name: production-db
spec:
  engine: postgresql
  version: "15"
  sizeGb: 100
```

---

## 3. Operator Örüntüsü ve Mutabakat Döngüsü (Reconciliation Loop)

Sadece CRD tanımlamak yetmez; CRD sadece bir veri şablonudur. Bu veriyi işleyecek olan bir beyne, yani **Controller**'a ihtiyaç vardır.

**Operator**, CRD ile tanımlanan "İstenen Durum" (Desired State) ile sistemin "Mevcut Durumunu" (Actual State) sürekli izleyen ve ikisi arasındaki farkı kapatmaya çalışan bir **Reconciliation Loop (Mutabakat Döngüsü)** çalıştırır:

```
   ┌───────────────┐
   │ İstenen Durum │ (Kullanıcının talep ettiği Database nesnesi)
   └───────────────┘
           │
           ▼  (Mutabakat / Reconcile)
   ┌───────────────┐
   │   Operator    │ ◄─── Düzeltici Eylem (Podları aç, diskleri bağla)
   └───────────────┘
           ▲
           │  (Mevcut Durumu Dinleme / Watch)
   ┌───────────────┐
   │ Mevcut Durum  │ (Kümede fiilen çalışan PostgreSQL podları)
   └───────────────┘
```

---

## 4. Operator Olgunluk Modeli (Operator Maturity Model)

Operatörlerin sunduğu otomasyon seviyesi 5 aşamada sınıflandırılır:

| Seviye | Kapasite Sınıfı | Açıklama |
| :---: | :--- | :--- |
| **1** | **Temel Kurulum (Basic Install)** | Uygulamanın Kubernetes üzerine ilk kurulumunu ve konfigürasyonunu yapar. |
| **2** | **Sorunsuz Güncelleme (Seamless Upgrades)** | Sürüm güncellemelerini, yama (patch) yönetimini otomatik yönetir. |
| **3** | **Tam Yaşam Döngüsü (Full Lifecycle)** | Yedek alma (backup), felaketten kurtarma (recovery) ve veri göçünü halleder. |
| **4** | **Derin Analiz (Deep Insights)** | Prometheus metriklerini, logları analiz eder ve alarm üretir. |
| **5** | **Otopilot (Auto Pilot)** | Anomali tespiti, otomatik yatay/dikey ölçeklendirme ve kendi kendini iyileştirme. |

---

## 5. Kubebuilder ile Operator Geliştirme (Go)

Kendi özel operatörünüzü geliştirmek için Kubernetes topluluğu tarafından sunulan resmi **Kubebuilder** SDK'sı (Go dili ile) en popüler araçtır.

### Geliştirme İskeleti Oluşturma

```bash
# Kubebuilder kurulumu
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/linux/amd64
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

# Projeyi başlatın
mkdir my-database-operator && cd my-database-operator
go mod init github.com/company/my-database-operator
kubebuilder init --domain company.com --repo github.com/company/my-database-operator

# Yeni bir API (CRD ve Controller) oluşturun
kubebuilder create api --group storage --version v1alpha1 --kind Database
```

### Go Kod Yapısı (Reconcile Mantığı)

`internal/controller/database_controller.go` içerisinde mutabakat döngüsü kodlanır:

```go
func (r *DatabaseReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. Kubernetes API'den talep edilen Database nesnesini çek
    var database storagev1alpha1.Database
    if err := r.Get(ctx, req.NamespacedName, &database); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. İş Mantığı: Veritabanı motoru çalışıyor mu?
    // Pod ve StatefulSet durumunu kontrol et, yoksa yenisini oluştur.

    // 3. Durum (Status) bilgisini güncelle
    database.Status.Phase = "Running"
    err := r.Status().Update(ctx, &database)

    return ctrl.Result{}, err
}
```

### Kümeye Dağıtım (Deploy)

```bash
# Go yapılarına göre CRD YAML şablonlarını üretin
make manifests

# CRD'leri Kubernetes kümesine yükleyin
make install

# Operator'ı lokal geliştirme modunda çalıştırın
make run

# Operator'ı Docker imajı olarak derleyip kümede yayınlayın
make docker-build IMG=my-operator:v1.0.0
make deploy IMG=my-operator:v1.0.0
```

---

## Özet

Custom Resource Definition (CRD) ve **Operator** örüntüsü, Kubernetes'i sadece bir konteyner çalıştırıcıdan çıkarıp tüm veri merkezini yöneten akıllı bir işletim sistemine dönüştürür. **CloudNativePG** (Postgres), **Strimzi** (Kafka) ve **Prometheus Operator** gibi popüler operatörler, modern altyapı yönetiminde insan operasyonlarını minimuma indirmektedir.
