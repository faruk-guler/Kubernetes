# ArgoCD ApplicationSet ile Çoklu Küme ve Monorepo Yönetimi

Tek bir uygulama veya isim alanı için bir adet ArgoCD `Application` kaynağı yazmak yeterlidir. Ancak 50 farklı Kubernetes kümesine (cluster) aynı uygulamayı deploy etmeniz gerektiğinde veya tek bir büyük Git deposunda (Monorepo) bulunan yüzlerce mikroservisi ayrı ayrı ArgoCD üzerinden yönetmek istediğinizde, tek tek YAML yazmak imkansızlaşır.

İşte bu noktada **ApplicationSet** devreye girer. ApplicationSet; belirlenen şablon üreteçlerine (**Generators**) göre otomatik, dinamik ve kurallı olarak yüzlerce ArgoCD `Application` nesnesi üreten üst seviye bir denetleyicidir.

---

## 1. Mimarisi ve Temel Mantığı

```text
┌──────────────────────────────────────┐
│       ApplicationSet Controller      │
└──────────────────┬───────────────────┘
                   │
                   ▼ (Okur)
┌──────────────────────────────────────┐
│        Generators (Üreteçler)        │
│  - List Generator (Statik Liste)     │
│  - Cluster Generator (Küme Listesi)  │
│  - Git Generator (Git Klasörleri)    │
└──────────────────┬───────────────────┘
                   │
                   ▼ (Dinamik Üretir)
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
[ App-Staging ] [ App-Prod ] [ App-EU ]  (ArgoCD Application CRD'leri)
```

---

## 2. List Generator (Statik Liste Üreteci)

En temel ve basit üreteçtir. YAML dosyasında elle belirttiğiniz statik bir liste (örneğin ortamlar ve isim alanları) üzerinden şablonu çözümler.

### Örnek List Generator Yapılandırması

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook-environments
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: staging
            url: https://staging-k8s.internal:6443
          - env: production
            url: https://prod-k8s.internal:6443
  template:
    metadata:
      name: '{{env}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/company/guestbook.git
        targetRevision: HEAD
        path: overlays/{{env}}
      destination:
        server: '{{url}}'
        namespace: guestbook
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

---

## 3. Cluster Generator (Kayıtlı Kümeler Üreteci)

ArgoCD sunucusuna tanımlanmış (kayıt edilmiş) tüm Kubernetes kümelerini otomatik olarak bulur ve her kümeye ilgili uygulamayı deploy eder. Kümeleri etiketlerine (`labels`) göre filtreleyebilir:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          type: production
# Üretilen değişkenler:
# {{name}}   -> Küme adı (Örn: prod-eu-central)
# {{server}} -> Küme API sunucu adresi (https://...)
```

---

## 4. Git Generator (Git Klasör ve Dosya Üreteci)

Git deposundaki dosya veya dizin yapılarını tarayarak dinamik uygulamalar üretir. Özellikle Monorepo mimarileri için hayati önem taşır.

### A. Git Dizin Üreteci (Directory Generator)

Git deposunda `apps/` klasörünün altındaki her bir alt klasörü (Örn: `frontend/`, `backend/`, `worker/`) otomatik olarak ayrı birer ArgoCD Application olarak tanımlar:

```yaml
generators:
  - git:
      repoURL: https://github.com/company/monorepo.git
      revision: HEAD
      directories:
        - path: apps/*
# Üretilen değişkenler:
# {{path.basename}} -> Klasör adı (Örn: auth-api)
# {{path}}          -> Dosya yolu (Örn: apps/auth-api)
```

### B. Git Dosya Üreteci (Files Generator)

Git reposu içinde bulunan JSON veya YAML dosyalarını okuyarak parametreleri oradan çeker:

```yaml
# config.json dosya örneği: {"name": "auth-api", "port": "8081"}
generators:
  - git:
      repoURL: 'https://github.com/company/config-repo.git'
      revision: HEAD
      files:
        - path: "clusters/**/config.json"
# JSON/YAML alanları şablonda {{name}}, {{port}} olarak doğrudan tüketilir.
```

---

## 5. Matrix Generator (Çok Boyutlu Üreteç)

İki farklı üretecin kartezyen çarpımını (kombinasyonunu) oluşturur. Örneğin: **[Kümeler]** listesi ile **[Uygulamalar]** listesini çarparak her uygulama için her kümeye ayrı bir deployment oluşturur:

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: https://github.com/company/gitops-apps.git
            directories:
              - path: services/*
        - clusters:
            selector:
              matchLabels:
                tier: production
# Çıktı: Her mikroservis x Her küme (Örn: name='{{name}}-{{path.basename}}')
```

---

## 6. Aşamalı Eşitleme (Progressive Syncs)

Tüm kümeleri aynı anda güncellemek yerine, önce Test/Staging kümelerini güncelleyip, başarılı olursa Prod kümelerine geçişi aşamalı olarak kontrol etmek için **Progressive Sync** kullanılır:

```yaml
spec:
  strategy:
    type: RollingSync
    rollingSync:
      steps:
        - matchExpressions:
            - key: environment
              operator: In
              values:
                - staging
          maxUpdate: 100%
        - matchExpressions:
            - key: environment
              operator: In
              values:
                - production
          maxUpdate: 20%
```

---

## 7. Yaşam Döngüsü ve Silme Politikaları (ApplicationSet Lifecycle)

Git üzerinden bir alt klasör silindiğinde veya bir küme listeden çıkarıldığında, ArgoCD'nin o uygulamayı kümeden nasıl sileceğini `syncPolicy.preserveResourcesOnDeletion` ve `applicationsSync` yönetir:

| Politika Modu | Davranış Biçimi | Uygun Senaryo |
| :--- | :--- | :--- |
| **`create-delete`** *(Varsayılan)* | Git'ten dizin veya küme silindiğinde ilgili `Application` nesnesi ve bağlı Kubernetes kaynakları kümeden tamamen temizlenir. | Dinamik preview veya test ortamları. |
| **`create-update`** | Yeni uygulamaları oluşturur ve günceller; fakat Git'ten silinen uygulamaları kümede muhafaza eder. | Kazara repo silinmelerine karşı üretim ortamlarını koruma. |
| **`create-only`** | Uygulamayı yalnızca bir kez oluşturur, sonraki Git değişikliklerini ve silme isteklerini yok sayar. | Bir kerelik bootstrap/şablon dağıtımları. |

> [!TIP]
> `spec.syncPolicy.preserveResourcesOnDeletion: true` olarak ayarlandığında, ApplicationSet tanımı silinse bile çalışan pod ve servisler kümede yetim (orphaned) olarak çalışmaya devam eder; kesinti yaşanmaz.

---

## 8. Hata Ayıklama ve Doğrulama (Debugging)

```bash
# 1. Tanımlı ApplicationSet listesini görüntüleme
kubectl get applicationset -n argocd

# 2. ApplicationSet üzerinde bir hata olup olmadığını inceleme (Event logs)
kubectl describe applicationset monorepo-services -n argocd

# 3. Kümeye uygulamadan önce şablonların üreteceği Application çıktılarını simüle etme:
argocd appset generate monorepo-services.yaml
```
