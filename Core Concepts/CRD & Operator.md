# CRD ve Operator Pattern

## Neden CRD ve Operator?

Kubernetes API, kendi başına yalnızca Pod, Deployment, Service gibi genel amaçlı kaynakları bilir. Peki ya "PostgreSQL Cluster" veya "Kafka Topic" gibi domain-specific kaynakları nasıl tanımlarız?

```
Standart K8s                Operator ile
─────────────               ─────────────
kubectl apply manifest  →   kubectl create postgrescluster my-db
Manuel failover         →   Operator otomatik failover yapar
Manuel yedek            →   Operator zamanlanmış yedek alır
```

## Custom Resource Definition (CRD)

CRD, Kubernetes API'sini kendi obje tiplerimizle genişletir.

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["cronSpec", "image"]
            properties:
              cronSpec:
                type: string
                pattern: '^(\d+|\*) (\d+|\*) (\d+|\*) (\d+|\*) (\d+|\*)$'
              image:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 10
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames: [ct]
```

CRD kurulduktan sonra artık şu şekilde kaynak oluşturabilirsiniz:

```yaml
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: my-cronjob
spec:
  cronSpec: "* * * * */5"
  image: my-cron-image:v1.0
  replicas: 2
```

## Operator Pattern

**Operator**, bir insanın yapacağı manuel operasyonel işlemleri (kurulum, yedekleme, failover, upgrade) kodla otomatize eden bir reconciliation loop'tur.

```
┌──────────┐     observe      ┌─────────────────┐
│  CRD     │───────────────→  │ Operator        │
│ (desired │                  │ Controller      │
│  state)  │                  │ (reconcile loop)│
└──────────┘ â†───────────── └─────────────────┘
               act (kubectl)        │
                                    ▼
                             Kubernetes API
                             (actual state)
```

**Bileşenler:**
- **CRD:** İstenen durumu (Desired State) tanımlar
- **Controller:** Mevcut durum ≠ İstenen durum olduğunda harekete geçer
- **RBAC:** Operator'ın API'ye ne yapabileceğini sınırlar

## Operator Olgunluk Modeli

| Seviye | Kapasite |
|:---:|:---|
| **1 - Basic Install** | Uygulama kurulumu |
| **2 - Seamless Upgrades** | Patch/minor upgrade yönetimi |
| **3 - Full Lifecycle** | Yedekleme, hata kurtarma |
| **4 - Deep Insights** | Metrikler, alertler, log analizi |
| **5 - Auto Pilot** | Otomatik ölçeklendirme, anomali tespiti |

## Hazır Operator'lar (2026 Standardı)

| Operator | Amaç | Kurulum |
|:---|:---|:---|
| CloudNativePG | PostgreSQL | `kubectl apply -f cnpg-manifests.yaml` |
| Prometheus Operator | Monitoring | `helm install prometheus kube-prometheus-stack` |
| Cert-manager | TLS sertifika | `helm install cert-manager oci://...` |
| Argo CD | GitOps | `kubectl apply -f argocd-install.yaml` |
| Kyverno | Policy | `helm install kyverno kyverno/kyverno` |
| Longhorn | Depolama | `helm install longhorn longhorn/longhorn` |
| KEDA | Autoscaling | `helm install keda kedacore/keda` |

## Kendi Operator'ınızı Yazın (Operator SDK)

```bash
# Operator SDK kurulumu
brew install operator-sdk

# Go tabanlı operator iskeleti oluştur
operator-sdk init --domain example.com --repo github.com/my-org/my-operator

# API oluştur (CRD + Controller)
operator-sdk create api --group cache --version v1alpha1 --kind Memcached --resource --controller

# Geliştirme döngüsü
make manifests    # CRD YAML'larını üret
make run          # Operator'ı lokalde çalıştır
make docker-build # Docker image oluştur
```

> [!TIP]
> Kendi operator'ınızı yazmadan önce OperatorHub.io sitesini kontrol edin. Büyük ihtimalle ihtiyacınız olan operatör zaten açık kaynak olarak mevcuttur.

---

## Kubebuilder ile Operator Geliştirme

**Kubebuilder**, Kubernetes'in resmi (SIG API Machinery) Operator geliştirme SDK'sıdır. Controller-Runtime kütüphanesi üzerine inşa edilmiştir.

### Kurulum ve Proje Başlatma

```bash
os=$(go env GOOS); arch=$(go env GOARCH)
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/${os}/${arch}
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

# Proje iskeleti oluştur
mkdir my-operator && cd my-operator
go mod init github.com/sirketim/my-operator
kubebuilder init --domain sirketim.com --repo github.com/sirketim/my-operator

# CRD + Controller dosyaları oluştur
kubebuilder create api --group game --version v1alpha1 --kind GameServer
```

### Reconcile Loop (İş Mantığı)

```go
// api/v1alpha1/gameserver_types.go
type GameServerSpec struct {
    MapName    string `json:"mapName,omitempty"`
    MaxPlayers int32  `json:"maxPlayers,omitempty"`
}

// internal/controller/gameserver_controller.go
func (r *GameServerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    var gameServer gamev1alpha1.GameServer
    if err := r.Get(ctx, req.NamespacedName, &gameServer); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    // İş mantığı: Deployment + Service oluştur/güncelle
    gameServer.Status.Condition = "Provisioned"
    return ctrl.Result{}, r.Status().Update(ctx, &gameServer)
}
```

### Cluster'a Deploy

```bash
make manifests   # Go struct'larından CRD YAML üret
make install     # CRD'leri cluster'a yükle
make run         # Operator'ı lokalde çalıştır (geliştirme)
make docker-build IMG=my-operator:v0.1.0
make deploy IMG=my-operator:v0.1.0
```

> [!TIP]
> Gerçek Cloud Native yaklaşım: iş kurallarını bir CI/CD sunucusunda değil, doğrudan Kubernetes Controller mekanizmasının içinde koşturmak.
