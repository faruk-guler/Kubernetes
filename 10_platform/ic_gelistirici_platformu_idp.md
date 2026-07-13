# Dahili Geliştirici Platformu (Internal Developer Platform - IDP) Mimarisi

Dahili Geliştirici Platformu (**IDP - Internal Developer Platform**), platform mühendisliği (Platform Engineering) ekipleri tarafından şirket içi yazılım ekiplerinin kullanımına sunulan; altyapı kurulumunu, mikroservis başlatmayı ve operasyonel araçları tek bir noktada birleştiren self-servis bir sistemdir. Amaç, geliştiricilerin Kubernetes'in karmaşık detaylarıyla uğraşmasını önlemek ve standartlara uygun, güvenli yolları (**Paved Roads / Golden Paths**) en kolay tercih haline getirmektir.

---

## 1. Dahili Geliştirici Platformunun (IDP) Sütunları

Bir IDP altyapısı temel olarak dört ana katmandan oluşur:

```
┌─────────────────────────────────────────────────────────────┐
│          Developer Portal (Arayüz: Backstage / Port)         │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Self-Servis İstek)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│    Altyapı Sağlayıcı (Crossplane / Terraform / ArgoCD)      │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Otonom Kurulum)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│    Kubernetes Kümeleri & Bulut Sağlayıcılar (AWS/GCP/AZ)     │
└─────────────────────────────────────────────────────────────┘
```

1. **Geliştirici Portalı (Developer Portal):** Geliştiricinin altyapıyı yönettiği, logları gördüğü ve servis kataloglarına eriştiği web arayüzüdür.
2. **Yazılım Kataloğu (Software Catalog):** Şirketteki tüm servisleri, kimin sorumlu olduğunu ve API bağımlılıklarını gösteren dinamik haritadır.
3. **Yazılım Şablonları (Software Templates):** Yeni bir servisi, veri tabanını veya CI/CD hattını saniyeler içinde otomatik başlatan (scaffolding) sihirbazlardır.
4. **Kod Yanı Dokümantasyon (TechDocs):** Kodla birlikte Git'te saklanan Markdown belgelerini portal üzerinde görselleştiren yapıdır.

---

## 2. Spotify Backstage Kurulumu ve Yapılandırması

Backstage üzerinde Kubernetes durumlarını canlı izlemek için Kubernetes eklentisi kurulmalıdır:

```bash
# 1. Backstage uygulamasına Kubernetes backend eklentisini ekleyin
yarn --cwd packages/backend add @backstage/plugin-kubernetes-backend
yarn --cwd packages/app add @backstage/plugin-kubernetes
```

### A. Yazılım Kataloğu Tanımı (`catalog-info.yaml`)

Geliştirilen uygulamanın Git reposuna eklenen ve Backstage tarafından taranan örnek dosya:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ic_gelistirici_platformu_idp_manifest_1.yaml](../Manifests/10_platform/ic_gelistirici_platformu_idp_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. TechDocs: Kod Yanı Dokümantasyon (Docs as Code)

TechDocs, dokümantasyonun kodla birlikte Git'te saklanmasını ve Backstage arayüzünde şık bir web sayfası olarak render edilmesini sağlar.

Projenizin kök dizinine bir `mkdocs.yaml` ekleyin:

```yaml
# mkdocs.yaml
site_name: "Payment Processor Dokümantasyonu"
plugins:
  - techdocs
nav:
  - Giriş: index.md
  - API Entegrasyonu: api.md
  - Hata Çözüm (Runbook): troubleshooting.md
```

Dokümantasyonu derleyip dışa aktarmak (build) için:

```bash
# Markdown dosyalarını derleyip HTML site çıktısı üretin:
npx @techdocs/cli generate --source-dir . --output-dir ./site
```

---

## 3. Crossplane ile Self-Service Altyapı Yönetimi

IDP mimarisinde geliştirici veritabanı veya bulut diski (S3) oluşturmak istediğinde bunu IT ekibine bilet açarak (ticket) istemez. Portaldaki formu doldurur. Backstage arka planda Kubernetes kümesine bir Crossplane altyapı kaynağı (Claim) gönderir. Crossplane ise AWS veya Azure'a giderek veritabanını oluşturur ve bağlantı bilgilerini geliştiricinin namespace'ine Secret olarak yazar.
*(Detaylı entegrasyonlar için bkz: [crossplane.md](crossplane.md))*

---

## 4. Port: Alternatif Modern IDP (SaaS Developer Portal)

Backstage'in en büyük dezavantajı Node.js ile yazılmış olması ve yönetilmesinin/kodlanmasının zorluğudur (Kod yazarak konfigüre edilir). **Port (getport.io)**, kod yazmadan tamamen JSON/YAML şablonları ile tasarlanabilen modern ve bulut tabanlı (SaaS) alternatif bir geliştirici portalıdır.

Port üzerinde, "Blueprint" adı verilen veri modelleri tanımlanır (Örn: Mikroservis, Küme, Veritabanı modelleri). Kubernetes üzerindeki kaynakları Port arayüzüne senkronize etmek için **Port K8s Exporter** aracı kümeye kurulur:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ic_gelistirici_platformu_idp_manifest_2.yaml](../Manifests/10_platform/ic_gelistirici_platformu_idp_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Platform Ekibi ve IDP Başarı Metrikleri (KPIs)

Bir platform ekibinin başarısı, geliştirici portalının ne kadar aktif kullanıldığı ve ekiplerin self-servis yeteneğiyle ölçülür.

```promql
# 1. Platform üzerinden oluşturulan toplam aktif mikroservis sayısı:
count(backstage_catalog_entity_count{kind="Component"})

# 2. Portalın haftalık / aylık aktif istek (kullanım) hızı:
rate(backstage_plugin_requests_total[7d])

# 3. Ortalamada yeni bir servisin kurulup canlıya çıkma süresi (Velocity):
# (Backstage Software Template tetiklenmesinden, ilk Kubernetes deployment anına kadar geçen süre)
histogram_quantile(0.50, backstage_scaffolder_task_duration_seconds_bucket)
```

> [!TIP]
> Platform Engineering ekibinin başarısının en kritik metriği: **"Manuel altyapı biletlerinin (IT tickets) sayısı"**. Eğer bu sayı sıfıra yaklaşıyorsa, yazılım ekipleri ihtiyaç duydukları her şeyi (veritabanı, repo, domain, SSL vb.) IDP üzerinden kendi başlarına yapabiliyor demektir.
