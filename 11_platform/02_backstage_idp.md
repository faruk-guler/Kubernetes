# Backstage ve Dahili Geliştirici Platformu (Internal Developer Platform - IDP)

Modern DevOps süreçlerinde, yazılım geliştiricilerin (developers) doğrudan karmaşık Kubernetes YAML dosyaları, ağ politikaları (network policies) ve bulut altyapı detaylarıyla boğuşması bir verimlilik kaybıdır. 2026 yılı altyapı standartlarında bu sorunu çözmek için **Platform Mühendisliği (Platform Engineering)** ve geliştiricilere self-servis altyapı sunan **Dahili Geliştirici Platformları (Internal Developer Platforms - IDP)** kullanılmaktadır.

---

## 1. Platform Mühendisliği Nedir?

DevOps kültürünün bir adım ötesi olan Platform Mühendisliği; yazılım geliştiricilerin üzerindeki kognitif (zihinsel) yükü azaltmak amacıyla ortak kullanılan altyapı, güvenlik ve dağıtım araçlarını tek bir self-servis portal altında birleştirmeyi hedefler.

```text
Eski Model (Yavaş & Bilet Odaklı):
  Yazılım Ekibi ──► IT Destek Talebi (Ticket) ──► Altyapı Ekibi ──► Günler Sonra Deployment

Modern Model (IDP & Self-Servis):
  Yazılım Ekibi ──► IDP Portalı (Tek Tık) ──► Golden Path Şablonu ──► Dakikalar İçinde Canlı Ortam
```

* **Golden Path (Altın Yol):** Platform ekibi tarafından önceden güvenlik, izleme ve dağıtım standartları belirlenmiş, geliştiricinin doğrudan kullanabileceği hazır ve güvenli yoldur.

---

## 2. Spotify Backstage: Servis Kataloğu ve Geliştirici Portalı

Spotify tarafından açık kaynak olarak geliştirilen **Backstage**, günümüzde IDP mimarilerinin merkezinde yer alan fiili standart geliştirici portalıdır. Tüm mikroservisleri, API dokümantasyonunu, CI/CD süreçlerini ve altyapı kaynaklarını tek bir katalogda toplar.

### Başlangıç Kurulumu

```bash
# 1. Yerel Backstage uygulamasını Node.js kullanarak oluşturun:
npx @backstage/create-app@latest

# 2. Hazır Docker imajını kullanarak çalıştırma:
docker pull backstage/backstage:latest
```

### catalog-info.yaml (Mikroservis Kimlik Kartı)

Her mikroservisin kendi git reposunun kök dizininde bulunan bu dosya, servisin Backstage üzerinde nasıl kataloglanacağını ve kimin sahipliğinde (owner) olduğunu tanımlar:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: "auth-service"
  description: "Kullanıcı doğrulama ve JWT token üreten merkezi mikroservis"
  tags:
    - "golang"
    - "grpc"
  links:
    - url: https://dashboard.company.com/auth-service
      title: Grafana Dashboard
      icon: dashboard
spec:
  type: service
  lifecycle: production
  owner: group:security-team
```

---

## 3. Golden Paths — Yazılım Şablonları (Software Templates)

Geliştiricilerin yeni bir mikroservise başlarken sıfırdan git reposu açması, CI/CD yazması ve Kubernetes YAML'larını hazırlaması yerine Backstage Software Templates kullanılır. Geliştirici sadece bir form doldurur ve Backstage arka planda şu adımları otomatik tamamlar:

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: go-microservice-template
  title: Go (Golang) Mikroservis Şablonu
spec:
  owner: group:platform-team
  type: service
  steps:
    - id: fetch-base
      name: Temel kod şablonunu (boilerplate) klonla
      action: fetch:template
      input:
        url: ./skeletons/go-service
    - id: publish-github
      name: GitHub üzerinde yeni repo oluştur
      action: publish:github
      input:
        repoUrl: github.com?owner=company&repo={{ parameters.name }}
    - id: register-catalog
      name: Servisi Backstage Kataloğuna Ekle
      action: catalog:register
```

---

## 4. Score — YAML Yazmadan Uygulama Tanımlama

Geliştiricilerin Kubernetes'in karmaşık pod tanımları yerine, uygulamanın çalışması için gerekli minimum ihtiyaçları (port, RAM limit, env config vb.) bulut-bağımsız tek bir dosyada tanımlamasını sağlayan formata **Score** denir.

### Örnek `score.yaml` Yapılandırması

```yaml
apiVersion: score.dev/v1b1
metadata:
  name: backend-api
containers:
  app:
    image: registry.company.com/backend-api:latest
    variables:
      ENV: "production"
      DB_HOST: "${resources.postgres.host}"
    resources:
      limits:
        memory: "512Mi"
        cpu: "1"
resources:
  postgres:
    type: postgres
```

*Platform Ekibi*, geliştiricinin yazdığı bu `score.yaml` dosyasını otomatik derleme (compile) araçlarıyla Kubernetes Deployment, Helm veya ArgoCD YAML dosyalarına dönüştürür. Geliştiricinin hiçbir Kubernetes bilgisine sahip olması gerekmez.

---

## 5. "You Build It, You Run It" (Sen Yazdın, Sen Yönet) Kültürü

Modern platform mühendisliğinde roller net ayrılmıştır:

* **Platform Ekibi (Platform Team):** Altyapıyı (Kubernetes, Grafana, Vault) ayakta tutar. Geliştiricilerin kullanacağı "Golden Path" şablonlarını tasarlar.
* **Yazılım Ekibi (Developers):** Kendi servislerini self-servis portaldan oluşturur. Uygulamanın loglarını (Loki), metriklerini (Grafana) ve uyarı kurallarını (PrometheusRule) kendisi yönetir ve izler.
