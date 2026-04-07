# Backstage ve Internal Developer Platform (IDP)

## 2.1 Platform Mühendisliği Nedir?

2026'da "Platform Mühendisliği" (Platform Engineering), DevOps'un bir adım ötesine geçmiştir. Geliştiricilerin Kubernetes YAML'larıyla boğuşması yerine, **Internal Developer Platforms (IDP)** üzerinden self-servis olarak kaynaklarını oluşturması standarttır.

```
Eski dünya:           Yeni dünya (2026):
Dev → IT Ticket   →   Dev → IDP Self-Servis
Dev → DevOps      →   Dev → Golden Path
Dev → YAML yaz    →   Dev → Form doldur
```

## 2.2 Backstage — Servis Kataloğu

Platform mühendisliğinin kalbi **Backstage**'dir (Spotify tarafından açık kaynak olarak geliştirilmiştir). Tüm mikroservislerin, dokümantasyonun, CI/CD pipeline'larının ve altyapı şablonlarının tek bir portalda yönetilmesini sağlar.

### Backstage Kurulumu

```bash
# Node.js gerektirir
npx @backstage/create-app@latest

# Docker ile çalıştır
docker pull backstage/backstage:latest
```

### catalog-info.yaml (Her Servis İçin)

```yaml
# Her repo'nun köküne bu dosyayı ekleyin
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: web-api
  description: Ana web API servisi
  annotations:
    github.com/project-slug: my-org/web-api
    prometheus.io/alert: web-api-alerts
    backstage.io/techdocs-ref: dir:.
  tags:
  - go
  - api
  - production
spec:
  type: service
  lifecycle: production
  owner: team-backend
  providesApis:
  - web-api-v2
  dependsOn:
  - component:postgres-service
  - component:redis-cache
```

## 2.3 Golden Paths — Self-Servis Repo Oluşturma

Backstage Software Templates ile geliştirici tek tıkla:
1. GitHub'da standart repo oluşturur
2. CI/CD pipeline'ı hazır gelir
3. Kubernetes namespace ve RBAC otomatik atanır
4. Monitoring dashboard'u Grafana'ya eklenir

```yaml
# Template tanımı (Backstage Software Template)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-microservice
  title: Yeni Mikroservis Oluştur
spec:
  type: service
  parameters:
  - title: Servis Bilgileri
    properties:
      name:
        title: Servis Adı
        type: string
      language:
        title: Dil
        type: string
        enum: [go, python, nodejs, java]
      team:
        title: Ekip
        type: string
  steps:
  - id: create-repo
    name: GitHub Repo Oluştur
    action: publish:github
    input:
      repoUrl: github.com?repo={{ parameters.name }}&owner=my-org
  - id: create-namespace
    name: K8s Namespace Oluştur
    action: kubernetes:apply
    input:
      manifest: |
        apiVersion: v1
        kind: Namespace
        metadata:
          name: {{ parameters.name }}
          labels:
            team: {{ parameters.team }}
```

## 2.4 Score — YAML'sız Uygulama Tanımlama

Geliştiricilerin YAML yerine ihtiyaçlarını JSON/YAML ile tanımladığı **Score** formatı:

```yaml
apiVersion: score.dev/v1b1
metadata:
  name: my-web-app
containers:
  web:
    image: my-registry/web-app:v1.2.3
    variables:
      PORT: "8080"
      LOG_LEVEL: "info"
resources:
  db:
    type: postgres          # Platform team bunu CloudNativePG ile sağlar
  cache:
    type: redis             # Platform team bunu Redis Operator ile sağlar
```

Platform ekibi bu tanımı alıp gerekli Kubernetes YAML'larına dönüştürür.

## 2.5 "You Build It, You Run It" Kültürü

2026 standartlarında geliştiriciler:
- Yazdıkları kodun cluster üzerindeki performansını (Grafana üzerinden) takip eder
- Loglarını (Loki üzerinden) okur
- Kendi alert kurallarını tanımlar (PrometheusRule)

Platform ekibi ise bu altyapının (Grafana, Loki, K8s) sağlıklı çalışmasını sağlar ve Golden Path'leri yönetir.

