# Internal Developer Platform (IDP)

Platform Engineering'in amacı geliştiricilere "golden path" sunmaktır — doğru şeyi yapmak en kolay yol olmalıdır. Internal Developer Platform, bu yolu somutlaştıran araçlar ve süreçler topluluğudur.

---

## Platform Engineering Nedir?

```
Geleneksel DevOps:             Platform Engineering:
Her ekip kendi infra kurar  →  Platform ekibi altyapıyı hazırlar
Developer K8s öğrenmek       Developer sadece uygulama yazar
zorunda                        (Self-service)
```

**IDP'nin sunduğu:**
- **Self-service** — Geliştirici "yeni servis kur" der, platform otomatik kurar
- **Golden paths** — Onaylanmış, güvenli, standart yollar
- **Developer portal** — Tüm servislerin, dokümantasyonun ve araçların tek yeri
- **Paved roads** — K8s karmaşıklığını saklar, geliştiriciye basit API sunar

---

## Backstage — Developer Portal

Spotify tarafından geliştirilen, CNCF'nin IDP standardı. Tüm mikroservisler, dokümanlar, CI/CD pipeline'ları ve altyapı tek portalda.

```bash
# Backstage kurulumu
npx @backstage/create-app@latest

# Kubernetes ile çalışmak için ek plugin
yarn --cwd packages/backend add @backstage/plugin-kubernetes-backend
yarn --cwd packages/app add @backstage/plugin-kubernetes
```

### Software Catalog (catalog-info.yaml)

Her servis kendi `catalog-info.yaml` dosyasını Git'e koyar:

```yaml
# my-service/catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: payment-service
  description: "Ödeme işlemlerini yöneten mikroservis"
  annotations:
    github.com/project-slug: company/payment-service
    backstage.io/techdocs-ref: dir:.
    backstage.io/kubernetes-id: payment-service
    prometheus.io/rule: |
      sum(rate(http_requests_total{service="payment"}[5m]))
  tags:
  - java
  - payments
  - critical
  links:
  - url: https://grafana.company.com/d/payment
    title: Grafana Dashboard
  - url: https://wiki.company.com/payment
    title: Runbook
spec:
  type: service
  lifecycle: production
  owner: team-payments
  system: ecommerce
  dependsOn:
  - component:database-service
  - component:notification-service
  providesApis:
  - payment-api-v2
```

### TechDocs — Kod Yanı Dokümantasyon

```yaml
# mkdocs.yml (servis root'unda)
site_name: Payment Service
docs_dir: docs/
nav:
  - Overview: index.md
  - Architecture: architecture.md
  - API Reference: api.md
  - Runbook: runbook.md
```

```bash
# TechDocs generate
npx @techdocs/cli generate --source-dir . --output-dir ./site
```

---

## Crossplane ile Self-Service Altyapı

Crossplane, geliştiricilerin `kubectl apply` ile bulut kaynakları (RDS, S3, Redis) oluşturmasını sağlar — AWS konsolu gerekmez.

```yaml
# Platform ekibi bir "DatabaseClaim" CRD tanımlar
apiVersion: database.company.com/v1alpha1
kind: DatabaseClaim
metadata:
  name: my-app-db
  namespace: team-alpha
spec:
  engine: postgresql
  version: "15"
  size: small          # platform ekibi "small" = db.t3.medium RDS olarak çevirir
  backupEnabled: true

# Arka planda Crossplane bu isteği gerçek AWS RDS kaynağına çevirir
```

---

## Port — Alternatif IDP Platformu

```yaml
# Port (getport.io) — no-code IDP
# blueprint tanımı
{
  "identifier": "microservice",
  "title": "Microservice",
  "properties": {
    "language": {"type": "string", "enum": ["Go", "Java", "Python"]},
    "team": {"type": "string"},
    "on_call": {"type": "string", "format": "email"},
    "slack_channel": {"type": "string"}
  },
  "relations": {
    "kubernetes_workload": {
      "target": "workload",
      "many": false
    }
  }
}
```

---

## Golden Path Template'leri

Tekton veya GitHub Actions ile yeni servis şablonu:

```yaml
# Backstage Software Template
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-microservice
  title: "Yeni Mikroservis Oluştur"
  description: "Go ile yazılmış, K8s'e deploy hazır mikroservis"
spec:
  owner: platform-team
  type: service

  parameters:
  - title: Servis Bilgileri
    required: [name, team, language]
    properties:
      name:
        title: Servis Adı
        type: string
        pattern: '^[a-z][a-z0-9-]*$'
      team:
        title: Sahip Ekip
        type: string
        ui:field: OwnerPicker
      language:
        title: Programlama Dili
        type: string
        enum: [go, java, python, nodejs]

  steps:
  - id: fetch-template
    name: Şablonu İndir
    action: fetch:template
    input:
      url: ./skeleton
      values:
        name: ${{ parameters.name }}
        team: ${{ parameters.team }}

  - id: publish
    name: GitHub'a Yayınla
    action: publish:github
    input:
      repoUrl: github.com?owner=company&repo=${{ parameters.name }}
      defaultBranch: main

  - id: register
    name: Backstage'e Kaydet
    action: catalog:register
    input:
      repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
      catalogInfoPath: /catalog-info.yaml

  output:
    links:
    - title: Repository
      url: ${{ steps.publish.output.remoteUrl }}
    - title: Backstage'de Aç
      entityRef: ${{ steps.register.output.entityRef }}
```

---

## Platform Ekibi Metrikleri

```promql
# Kaç servis self-service ile oluşturuldu?
count(backstage_catalog_entity_count{kind="Component"})

# Developer portal aktif kullanıcıları
rate(backstage_plugin_requests_total[7d])

# Ortalama "yeni servis" kurulum süresi
# (Backstage Template tetiklenme → ilk deployment)
histogram_quantile(0.50, backstage_scaffolder_task_duration_seconds_bucket)
```

> [!TIP]
> Platform Engineering başarısının ölçüsü: geliştiricilerin platform ekibine bağımlılığının azalması. "Kaç PR platform ekibine gitti?" metriğini takip edin — azalıyorsa platform iyi çalışıyor demektir.
