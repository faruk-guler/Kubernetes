# GitOps ile GitLab CI/CD

GitLab, hem CI/CD hem de Git deposunu tek platformda sunar. Kubernetes entegrasyonu Agent (Pull tabanlı) veya Runner üzerinden sağlanır.

---

## GitLab Agent for Kubernetes (KAS)

GitLab'ın modern Kubernetes entegrasyon yöntemi. Push değil Pull-based — cluster güvenlik duvarı arkasında olsa bile çalışır.

```bash
# GitLab UI → Infrastructure → Kubernetes clusters → Connect a cluster
# Verilen komutu cluster'da çalıştır:
helm repo add gitlab https://charts.gitlab.io
helm install gitlab-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --create-namespace \
  --set config.token=<agent-token> \
  --set config.kasAddress=wss://kas.gitlab.com
```

### Agent Yapılandırması

```yaml
# .gitlab/agents/production-agent/config.yaml (git repo'da)
gitops:
  manifest_projects:
  - id: company/k8s-manifests       # Bu repo'daki manifesti uygula
    default_namespace: production
    paths:
    - glob: 'apps/**/*.yaml'
    reconciliation_interval: 5m     # 5 dakikada bir sync

ci_access:
  projects:
  - id: company/backend-api         # Bu CI job'ları cluster'a erişebilir
  - id: company/frontend-app
  groups:
  - id: company/microservices       # Bu grup altındaki tüm projeler
```

---

## Tam GitLab CI/CD Pipeline

```yaml
# .gitlab-ci.yml
variables:
  IMAGE_NAME: $CI_REGISTRY_IMAGE
  IMAGE_TAG: $CI_COMMIT_SHORT_SHA
  KUBE_CONTEXT: company/k8s-configs:production-agent

stages:
  - validate
  - test
  - security
  - build
  - deploy-staging
  - integration-test
  - deploy-production

# ── VALIDATE ──────────────────────────────────────────────
lint:
  stage: validate
  image: python:3.12-slim
  script:
    - pip install ruff
    - ruff check .
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

yaml-lint:
  stage: validate
  image: cytopia/yamllint:1.35
  script:
    - yamllint k8s/

# ── TEST ──────────────────────────────────────────────────
unit-test:
  stage: test
  image: python:3.12-slim
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: testdb
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://postgres:test@postgres/testdb
  script:
    - pip install -r requirements.txt
    - pytest tests/unit/ --cov=app --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
      junit: junit.xml

# ── SECURITY ──────────────────────────────────────────────
sast:
  stage: security
  image: semgrep/semgrep:1.77.0
  script:
    - semgrep --config=auto --json > semgrep.json
  artifacts:
    reports:
      sast: semgrep.json

container-scan:
  stage: security
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy image
        --format sarif
        --output trivy-report.sarif
        --severity HIGH,CRITICAL
        --exit-code 1
        $IMAGE_NAME:$IMAGE_TAG
  dependencies: [build]
  artifacts:
    reports:
      container_scanning: trivy-report.sarif

# ── BUILD ─────────────────────────────────────────────────
build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:debug
    entrypoint: [""]
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"$CI_REGISTRY\":{\"auth\":\"$(echo -n $CI_REGISTRY_USER:$CI_REGISTRY_PASSWORD | base64)\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor
        --context "$CI_PROJECT_DIR"
        --dockerfile "$CI_PROJECT_DIR/Dockerfile"
        --destination "$IMAGE_NAME:$IMAGE_TAG"
        --destination "$IMAGE_NAME:latest"
        --cache=true
        --cache-ttl=24h
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_TAG

# ── DEPLOY STAGING ────────────────────────────────────────
deploy-staging:
  stage: deploy-staging
  image: bitnami/kubectl:1.32.0
  environment:
    name: staging
    url: https://staging.company.com
    on_stop: stop-staging
  before_script:
    - kubectl config use-context $KUBE_CONTEXT
  script:
    - |
      kubectl set image deployment/api \
        app=$IMAGE_NAME:$IMAGE_TAG \
        -n staging
      kubectl rollout status deployment/api \
        -n staging \
        --timeout=5m
    - echo "Staging deploy başarılı: $IMAGE_TAG"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

stop-staging:
  stage: deploy-staging
  environment:
    name: staging
    action: stop
  script:
    - kubectl scale deployment/api --replicas=0 -n staging
  when: manual
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

# ── INTEGRATION TEST ──────────────────────────────────────
integration-test:
  stage: integration-test
  image: grafana/k6:0.52.0
  script:
    - k6 run
        --vus 10
        --duration 2m
        --threshold 'http_req_failed<0.01'
        --threshold 'http_req_duration{p(99)}<500'
        tests/load/smoke.js
  environment:
    name: staging
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

# ── DEPLOY PRODUCTION ─────────────────────────────────────
deploy-production:
  stage: deploy-production
  image: bitnami/kubectl:1.32.0
  environment:
    name: production
    url: https://api.company.com
  before_script:
    - kubectl config use-context $KUBE_CONTEXT
  script:
    - |
      # GitOps repo'daki image tag'ini güncelle
      git clone https://oauth2:${GITOPS_TOKEN}@gitlab.company.com/company/k8s-configs
      cd k8s-configs
      sed -i "s|image:.*|image: $IMAGE_NAME:$IMAGE_TAG|" \
        apps/api/production/deployment.yaml
      git config user.email "ci@company.com"
      git config user.name "GitLab CI"
      git add -A
      git commit -m "ci: api → $IMAGE_TAG"
      git push origin main
      # GitLab Agent bu değişikliği algılayıp sync eder
  when: manual      # Manuel onay gerekli
  rules:
    - if: $CI_COMMIT_TAG    # Sadece tag'den production
```

---

## GitLab Environments & Deployments

```yaml
# Ortam listesi ve geçmişi GitLab UI'da görünür
# Infrastructure → Environments

# Ortam durdurma (maliyet tasarrufu)
stop-review:
  stage: cleanup
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop
  script:
    - kubectl delete namespace review-$CI_COMMIT_REF_SLUG --ignore-not-found
  when: manual
  rules:
    - if: $CI_MERGE_REQUEST_ID
```

---

## Auto DevOps (Hazır Pipeline)

```yaml
# .gitlab-ci.yml (minimum — Auto DevOps aktif et)
include:
  - template: Auto-DevOps.gitlab-ci.yml

variables:
  KUBE_NAMESPACE: production
  KUBE_INGRESS_BASE_DOMAIN: company.com
  # Auto DevOps otomatik yapar:
  # - Docker build
  # - Trivy scan
  # - Staging deploy
  # - DAST (Dynamic Application Security Testing)
  # - Production deploy (manuel onay)
```

---

## Reusable CI Components (GitLab CI/CD Components)

```yaml
# .gitlab/components/deploy/template.yml
spec:
  inputs:
    environment:
      description: "Target environment"
    image-tag:
      description: "Image tag to deploy"

---
deploy-component:
  image: bitnami/kubectl:1.32.0
  script:
    - kubectl set image deployment/api
        app=$[[ inputs.image-tag ]]
        -n $[[ inputs.environment ]]
    - kubectl rollout status deployment/api
        -n $[[ inputs.environment ]]
```

```yaml
# Başka projede kullan
include:
  - component: gitlab.company.com/platform/ci-components/deploy@main
    inputs:
      environment: staging
      image-tag: $IMAGE_TAG
```

> [!TIP]
> GitLab'ın **Merge Request Pipeline** özelliğini kullanın — sadece main'e merge olan kod production'a gider, her PR kendi staging ortamında test edilir.
