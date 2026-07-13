# ArgoCD ApplicationSet ile Çoklu Küme ve Monorepo Yönetimi

Tek bir uygulama veya isim alanı için bir adet ArgoCD `Application` kaynağı yazmak yeterlidir. Ancak 50 farklı Kubernetes kümesine (cluster) aynı uygulamayı deploy etmeniz gerektiğinde veya tek bir büyük Git deposunda (Monorepo) bulunan yüzlerce mikroservisi ayrı ayrı ArgoCD üzerinden yönetmek istediğinizde, tek tek YAML yazmak imkansızlaşır.

İşte bu noktada **ApplicationSet** devreye girer. ApplicationSet; belirlenen şablon üreteçlerine (**Generators**) göre otomatik, dinamik ve kurallı olarak yüzlerce ArgoCD `Application` nesnesi üreten üst seviye bir denetleyicidir.

---

## 1. Mimarisi ve Temel Mantığı

```
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

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_applicationset_manifest_1.yaml](../Manifests/09_gitops/argocd_applicationset_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Cluster Generator (Kayıtlı Kümeler Üreteci)

ArgoCD sunucusuna tanımlanmış (kayıt edilmiş) tüm Kubernetes kümelerini otomatik olarak bulur ve her kümeye ilgili uygulamayı deploy eder. Kümeleri etiketlerine (labels) göre filtreleyebilir.

### Örnek Cluster Generator Yapılandırması

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_applicationset_manifest_2.yaml](../Manifests/09_gitops/argocd_applicationset_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Git Generator (Git Klasör ve Dosya Üreteci)

Git deposundaki dosya veya dizin yapılarını tarayarak dinamik uygulamalar üretir. Özellikle Monorepo (tek repoda çoklu servis) mimarileri için hayati önem taşır.

### A. Git Dizin Üreteci (Directory Generator)

Git deposunda `apps/` klasörünün altındaki her bir alt klasörü (Örn: `frontend/`, `backend/`, `worker/`) otomatik olarak ayrı birer ArgoCD Application olarak tanımlar:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_applicationset_manifest_4.yaml](../Manifests/09_gitops/argocd_applicationset_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Git Dosya Üreteci (Files Generator)

Git reposu içinde bulunan JSON veya YAML dosyalarını okuyarak parametreleri oradan çeker:

```yaml
# config.json dosyası içeriği: {"name": "auth-api", "port": "8081"}
generators:
- git:
    repoURL: 'https://github.com/company/config-repo.git'
    revision: HEAD
    files:
    - path: "clusters/**/config.json"
```

---

## 5. Matrix Generator (Çok Boyutlu Üreteç)

İki farklı üretecin kartezyen çarpımını (kombinasyonunu) oluşturur. Örneğin: **[Kümeler]** listesi ile **[Uygulamalar]** listesini çarparak her uygulama için her kümeye ayrı bir deployment oluşturur.

### Örnek Matrix Generator Yapılandırması

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_applicationset_manifest_3.yaml](../Manifests/09_gitops/argocd_applicationset_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Aşamalı Eşitleme (Progressive Syncs)

Tüm kümeleri aynı anda güncellemek yerine, önce Test/Staging kümelerini güncelleyip, başarılı olursa Prod kümelerine geçişi aşamalı olarak kontrol etmek için **Progressive Sync** kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [argocd_applicationset_manifest_5.yaml](../Manifests/09_gitops/argocd_applicationset_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. Yaşam Döngüsü Politikası (ApplicationSet Policies)

Git üzerinden bir alt klasör veya yapılandırma silindiğinde Kubernetes üzerindeki uygulamanın otomatik silinip silinmeyeceğini `syncPolicy.reclaimPolicy` ile kontrol edebilirsiniz:

```yaml
spec:
  syncPolicy:
    # 1. CreateOnly: Sadece oluşturur, Git'ten silinse dahi kümeden silmez.
    # 2. CreateUpdate: Oluşturur ve günceller, silme yapmaz.
    # 3. CreateDelete (Varsayılan): Git'ten silinen dosyayı kümeden de siler.
    preserveResourcesOnDeletion: false # false = Git'ten silinirse K8s'ten de sil!
```

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
