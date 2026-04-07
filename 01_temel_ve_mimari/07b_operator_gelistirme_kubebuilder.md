# Golang ve Kubebuilder ile Operator Geliştirme

Önceki bölümlerde Custom Resource Definition (CRD) konseptini işlemiştik. Ancak bir "Black Belt" K8s mimarı sadece hazır operatörleri kullanmakla yetinmez, firmasının spesifik iş mantığını işleyecek kendi **Kubernetes Operator**'ını sıfırdan Go ile yazar. 

---

## 7.1.1 Başlangıç: Kubebuilder Nedir?

**Kubebuilder**, Kubernetes Control Plane'inin kalbi olan **Controller-Runtime** kütüphanesini kullanarak CRD ve Controller iskeleti üreten, resmi (SIG API Machinery) SDK aracıdır.

- `GOPATH` ve Go kurulu olmalı.
- Docker, `make` aracı ve `kustomize` kurulu olmalı.

```bash
# Kubebuilder kurulumu (Mac/Linux)
os=$(go env GOOS)
arch=$(go env GOARCH)
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/${os}/${arch}
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/
```

---

## 7.1.2 Proje Başlatma (Scaffolding)

Şirketiniz için `OyunSunucusu` (GameServer) adında bir kaynak yaratacağımızı düşünelim.

```bash
mkdir my-operator && cd my-operator
go mod init github.com/sirketim/my-operator

# Projeyi başlat
kubebuilder init --domain sirketim.com --repo github.com/sirketim/my-operator

# CRD API ve Controller dosyalarını oluştur
kubebuilder create api --group game --version v1alpha1 --kind GameServer
```

---

## 7.1.3 İş Mantığını Kodlama (The Reconcile Loop)

Kubebuilder sizin için `api/v1alpha1/gameserver_types.go` dosyasını oluşturdu. Burada istenen durumu (Desired State - Spec) belirlersiniz:

```go
// Spec alanı (İstediğimiz Durum)
type GameServerSpec struct {
    MapName     string `json:"mapName,omitempty"`
    MaxPlayers  int32  `json:"maxPlayers,omitempty"`
}

// Status alanı (Gerçekleşen Durum)
type GameServerStatus struct {
    ActivePlayers int32 `json:"activePlayers"`
    Condition     string `json:"condition"`
}
```

Daha sonra Kalp atışının gerçekleştiği `internal/controller/gameserver_controller.go` içerisindeki `Reconcile` fonksiyonuna kodlar yazılır.

```go
func (r *GameServerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := log.FromContext(ctx)

    // 1. İlgili Custom Resource'i getir (Sizin GameServer objeniz)
    var gameServer gamev1alpha1.GameServer
    if err := r.Get(ctx, req.NamespacedName, &gameServer); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. Kendi İş Mantığınız (Örn: Bu Server için Deployment+Service yatılıp yaratılmadığı)
    log.Info("GameServer kontrol ediliyor", "Harita", gameServer.Spec.MapName)
    
    // ... Pod oluşturma, konfigürasyonu K8s'e basma metotları ...

    // 3. Status güncelleme ve döngüden çıkış
    gameServer.Status.Condition = "Provisioned"
    err := r.Status().Update(ctx, &gameServer)
    
    return ctrl.Result{}, err
}
```

---

## 7.1.4 Cluster'a Dağıtma

Yazdığınız Controller'ın CRD'lerini YAML olarak dışa çıkarmak ve K8s'e entegre etmek:

```bash
# Go kodunu okuyup CRD manifestleri oluşturur
make manifests

# CRD'leri aktif cluster'a yükler
make install

# Operatörü bilgisayarınızda (dışarıdan) cluster'a bağlayarak çalıştırın 
make run
```

Artık K8s'e `kind: GameServer` manifesti verdiğiniz an, terminalinizdeki Go terminali o objeyi yakalayacak ve belirttiğiniz Pod/Service kurulumunu saniyeler içinde yapacaktır!

> [!TIP]
> Çoğu şirket "GitOps ile Jenkins/Runner" kullanıp veritabanı vs oluşturmaya çalışır. **Gerçek Cloud Native yaklaşım**, bir Operator yazmak ve iş kurallarını bir CI/CD sunucusunda değil, doğrudan K8s Controller mekanizmasının içinde koşmaktır.

---
*← [CRD ve Operator](07_crd_ve_operator.md) | [Ana Sayfa](../README.md)*
