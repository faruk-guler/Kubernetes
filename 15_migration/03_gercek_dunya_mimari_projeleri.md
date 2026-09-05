# Gerçek Dünya Projeleri ve Üretim Mimarileri

Bu bölümde, teorik ve pratik bilgileri birleştirerek, üretim ortamlarında (Production) canlıda çalışan iki farklı uçtan uca mimariyi kurgulayacağız: **Full-Stack E-Ticaret Platformu Mimarisi** ve **Kurumsal GitOps Depo Yapısı**.

---

## Proje 1: Full-Stack E-Ticaret Platformu Mimarisi

Bu projede bir E-Ticaret uygulamasının gereksinim duyduğu tüm katmanlar (Frontend, HPA destekli Backend API, PostgreSQL StatefulSet Veritabanı, Redis In-Memory Cache, Ingress ve TLS) tek bir mimaride birleştirilmiştir.

```text
                                [ İNTERNET TRAFİĞİ ]
                                         |
                                         v (HTTPS: Port 443)
                           [ Nginx Ingress Controller ]
                           (cert-manager SSL Sertifikası)
                                         |
             +---------------------------+---------------------------+
             | Domain: store.mycompany.com                           | Path: /api/*
             v                                                       v
   [ Frontend Deployment ]                               [ Backend API Deployment ]
   (3 Replicas - React/Next.js)                          (Autoscaled HPA: 3-15 Replicas)
                                                                     |
                                           +-------------------------+-------------------------+
                                           |                                                   |
                                           v                                                   v
                               [ PostgreSQL StatefulSet ]                          [ Redis StatefulSet ]
                               (Primary DB + 50GB EBS PVC)                         (Session & Cart Cache)
```

### Modüler Mimari Bileşenleri ve Üretim Kararları

Bu mimaride, monolitik devasa YAML dosyaları kopyalamak yerine her katman bağımsız sorumluluklarına ve üretim gereksinimlerine göre yapılandırılır:

| Katman | Seçilen Kubernetes Kaynağı | Kritik Üretim Parametresi | Mimari Gerekçe |
| :--- | :--- | :--- | :--- |
| **Veri Katmanı** | `StatefulSet` + Headless Service | `volumeClaimTemplates` (50Gi SSD) | Pod yeniden başlasa bile aynı kalıcı diske (PVC) ve kararlı ağ kimliğine (`postgres-db-0`) bağlanması zorunludur. |
| **Uygulama Katmanı** | `Deployment` + HPA | `maxSurge: 1`, `maxUnavailable: 0` | Güncellemeler sırasında mevcut çalışan hiçbir pod kapatılmadan yenisi ayağa kalkar; sıfır kesinti (Zero-Downtime) garanti edilir. |
| **Trafik & TLS** | `Ingress` + `cert-manager` | `cluster-issuer: letsencrypt-production` | SSL/TLS sonlandırması Ingress seviyesinde yapılır; sertifikalar otomatik yenilenir ve backend yükten kurtarılır. |

---

### Üretim Ortamı Tasarım İlkeleri

Bu mimarinin yüksek erişilebilirlik (HA) ve veri güvenliğini sağlayan üç temel ilkesi:

1. **Veri Güvenliği ve İzolasyon:** Veritabanı ve önbellek sistemleri rastgele düğümlere dağıtılmak yerine `StatefulSet` ile yönetilir. Her kopya bağımsız bir `volumeClaimTemplates` diskiyle eşleşir; pod çökse veya taşınsa dahi veriler asla kaybolmaz.
2. **Sıfır Kesintili Güncelleme (Zero-Downtime):** Uygulama katmanında `RollingUpdate` parametreleri `maxSurge: 1` ve `maxUnavailable: 0` olarak kilitlenir. Yeni sürüm sağlıklı ve hazır (`readyz`) olmadan çalışan tek bir eski pod dahi kapatılmaz; kullanıcı trafiği hiçbir an kesintiye uğramaz.
3. **Merkezi Güvenlik ve TLS:** SSL/TLS sertifika yönetimi uygulama koduna bırakılmaz. Ingress düzeyinde `cert-manager` entegrasyonu ile Let's Encrypt sertifikaları dinamik olarak üretilir, yenilenir ve HTTPS trafiği doğrudan Ingress Controller tarafından karşılanır.


---

## Proje 2: Kurumsal GitOps Depo Yapısı (Kustomize + ArgoCD)

Büyük ölçekli kurumlarda tüm ortamlar (Dev, Staging, Prod) tek bir klasörde karıştırılmaz. GitOps standartlarına uygun kurumsal klasör mimarisi şu şekilde kurgulanmalıdır:

```text
gitops-enterprise-repo/
├── apps/
│   ├── order-service/
│   │   ├── base/                     <-- Tüm ortamlar için ortak YAML'lar
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       ├── development/          <-- Dev Ortamı (Replica: 1, Debug Logs)
│   │       │   ├── kustomization.yaml
│   │       │   └── patch-env.yaml
│   │       └── production/           <-- Prod Ortamı (Replica: 10, HPA, TLS)
│   │           ├── kustomization.yaml
│   │           └── patch-resources.yaml
│   └── payment-service/
│       ├── base/
│       └── overlays/
└── argocd-infrastructure/
    ├── dev-applicationset.yaml       <-- Dev ortamını otomatik bağlayan ArgoCD kuralı
    └── prod-applicationset.yaml      <-- Prod ortamını otomatik bağlayan ArgoCD kuralı
```

Bu modüler yapı sayesinde bir yazılımcı sadece `overlays/development` klasöründe değişiklik yaparken, üretim ortamı (`overlays/production`) güvende kalır ve tüm süreç Git PR (Pull Request) onay mekanizmasıyla yürütülür.
