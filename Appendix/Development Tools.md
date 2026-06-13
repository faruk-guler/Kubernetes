# Development Tools — Kubernetes İç Döngü Geliştirme

Lokal makinede kod yazarken Kubernetes cluster'ına hızlıca deploy edip test etmek için kullanılan araçlar. "Inner loop" geliştirme sürecini hızlandırır.

---

## Araç Seçim Rehberi

```
Telepresence → Servis trafiğini lokal makineye yönlendir
               (cluster'da çalışıyormuş gibi debug et)

Skaffold     → Kod değişince otomatik build → push → deploy
               (CI/CD pipeline'ın lokal versiyonu)

Tilt         → Skaffold gibi ama görsel dashboard ile
               (multi-service lokal geliştirme)

DevSpace     → Konteyner içinde hot-reload
               (dosya kaydet → konteynere senkronize et, restart yok)
```

---

## Telepresence — Cluster Trafiğini Lokale Al

Cluster'daki bir servise gelen trafiği lokal makinene yönlendir. Servis cluster'da çalışıyormuş gibi diğer servislerle konuşur, ama kod senin makinende.

```bash
# Kurulum
brew install datawire/blackbird/telepresence   # macOS
# Windows: Chocolatey veya MSI installer

# Cluster'a bağlan
telepresence connect

# Şimdi cluster içi DNS'e doğrudan erişebilirsin
curl http://api-service.production.svc.cluster.local   # ✅ lokal makineden!

# Belirli servisi lokale yönlendir (intercept)
telepresence intercept api-service \
  --namespace production \
  --port 8080:8080 \
  --env-file .env.intercept    # Servisin environment değişkenlerini al

# Artık production'daki api-service trafiği lokal 8080'e geliyor
# Kendi servisini lokalde başlat
go run main.go   # ya da node server.js, python app.py vb.

# İnteresepti sonlandır
telepresence leave api-service-production

# Bağlantıyı kes
telepresence quit
```

```bash
# Personal intercept (sadece belirli header'ı lokale yönlendir)
telepresence intercept api-service \
  --namespace production \
  --port 8080 \
  --http-header x-debug-user=my-username
# Diğer kullanıcılar cluster'daki servisi görmeye devam eder
```

---

## Skaffold — Otomatik Build-Deploy Döngüsü

```bash
# Kurulum
brew install skaffold    # macOS
# Linux:
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
sudo install skaffold /usr/local/bin/
```

```yaml
# skaffold.yaml — proje kökünde
apiVersion: skaffold/v4beta11
kind: Config
metadata:
  name: api-service

build:
  artifacts:
  - image: ghcr.io/company/api
    docker:
      dockerfile: Dockerfile
    sync:
      # Dockerfile rebuild olmadan dosya senkronize et
      infer:
      - "**/*.go"    # Go dosyası değişince restart yerine sync

deploy:
  kubectl:
    manifests:
    - k8s/deployment.yaml
    - k8s/service.yaml

# veya Helm ile
# deploy:
#   helm:
#     releases:
#     - name: api
#       chartPath: ./charts/api

portForward:
- resourceType: service
  resourceName: api-service
  namespace: production
  port: 80
  localPort: 8080    # localhost:8080 → cluster servisine

profiles:
- name: production
  deploy:
    kubectl:
      flags:
        global: ["-n", "production"]
```

```bash
# Geliştirme modu — dosya değişince otomatik deploy
skaffold dev

# Tek seferlik deploy
skaffold run

# Production profili ile deploy
skaffold run -p production

# Build sadece (deploy yok)
skaffold build --push

# Temizle (deploy edilenleri sil)
skaffold delete
```

---

## Tilt — Görsel Multi-Service Geliştirme

```bash
# Kurulum
brew install tilt    # macOS
# Linux:
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
```

```python
# Tiltfile — Python benzeri syntax
# Servis bağımlılıklarını ve build adımlarını tanımla

# Frontend
docker_build('ghcr.io/company/frontend', './frontend',
  live_update=[
    sync('./frontend/src', '/app/src'),   # Hot reload
  ])

k8s_yaml('./k8s/frontend.yaml')
k8s_resource('frontend',
  port_forwards='3000:3000',
  labels=['frontend'])

# API
docker_build('ghcr.io/company/api', './api')
k8s_yaml('./k8s/api.yaml')
k8s_resource('api',
  port_forwards='8080:8080',
  resource_deps=['postgres'],   # postgres hazır olunca başlat
  labels=['backend'])

# Postgres
k8s_yaml('./k8s/postgres.yaml')
k8s_resource('postgres',
  port_forwards='5432:5432',
  labels=['infra'])
```

```bash
# Tilt UI ile başlat (http://localhost:10350)
tilt up

# CI modunda çalıştır (UI yok)
tilt ci

# Temizle
tilt down
```

---

## DevSpace — Konteyner İçi Hot Reload

```bash
# Kurulum
brew install devspace    # macOS
# Windows:
# choco install devspace

# Projeyi başlat
devspace init
```

```yaml
# devspace.yaml
version: v2beta1
name: api-service

pipelines:
  dev:
    run: |-
      run_dependencies --all
      create_deployments --all
      start_dev app

deployments:
  app:
    helm:
      chart:
        path: ./charts/api

dev:
  app:
    imageSelector: ghcr.io/company/api
    devImage: golang:1.22-alpine    # Geliştirme ortamı image'ı
    sync:
    - path: ./:/app
      excludePaths:
      - .git/
      - vendor/
    terminal:
      command: "/bin/bash"
    ports:
    - port: "8080"
    proxyCommands:
    - command: go
    - command: git
```

```bash
# Geliştirme başlat
devspace dev        # Konteyner içinde shell açar, dosyalar senkronize

# Deploy
devspace deploy

# Temizle
devspace purge
```

---

## Araç Karşılaştırması

| | Telepresence | Skaffold | Tilt | DevSpace |
|:--|:--|:--|:--|:--|
| **Kullanım** | Cluster trafiğini lokale al | Build→Deploy otomasyonu | Multi-service dashboard | Konteyner içi geliştirme |
| **Hot reload** | ❌ | ✅ (sync ile) | ✅ | ✅ |
| **UI** | ❌ | ❌ | ✅ | ❌ |
| **Multi-service** | ✅ | Kısmen | ✅ | ❌ |
| **En iyi için** | Prod bağımlısı debug | CI/CD lokal test | Mikroservis geliştirme | Tek servis geliştirme |

> [!TIP]
> **Başlangıç için:** Tek servis → **DevSpace** veya **Skaffold**. Çok servis → **Tilt**. Cluster'daki canlı servise erişim gerekiyorsa → **Telepresence**.
