# CI/CD Pipeline Patterns

Kubernetes ile entegre CI/CD pipeline'ları, "kod commit edildiğinde otomatik olarak cluster'a deploy edilir" akışını sağlar. Bu bölüm Tekton, GitHub Actions ve GitLab CI entegrasyonlarını kapsar.

---

## CI/CD Olgunluk Modeli

```
Seviye 0: Elle deploy (kubectl apply)
Seviye 1: Script ile deploy (CI çalıştırır kubectl)
Seviye 2: Image build + push + deploy (CI/CD pipeline)
Seviye 3: GitOps (ArgoCD/Flux — repo = gerçek)
Seviye 4: Canary + otomatik rollback (Argo Rollouts)
```

---

## GitHub Actions — Kubernetes Deploy

### Temel Pipeline

```yaml
# .github/workflows/deploy.yaml
name: Build and Deploy

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}

    steps:
    - uses: actions/checkout@v4

    - name: Docker meta
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=sha,prefix=sha-
          type=ref,event=branch
          type=semver,pattern={{version}}

    - name: Login to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Build and Push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: ${{ github.event_name != 'pull_request' }}
        tags: ${{ steps.meta.outputs.tags }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy-staging:
    needs: build-and-push
    runs-on: ubuntu-latest
    environment: staging
    if: github.event_name != 'pull_request'

    steps:
    - uses: actions/checkout@v4

    - name: Configure kubectl
      uses: azure/k8s-set-context@v3
      with:
        method: kubeconfig
        kubeconfig: ${{ secrets.KUBECONFIG_STAGING }}

    - name: Deploy to Staging
      run: |
        IMAGE_TAG="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}"
        kubectl set image deployment/web-app \
          app=$IMAGE_TAG \
          -n staging
        kubectl rollout status deployment/web-app -n staging --timeout=5m

    - name: Run Smoke Tests
      run: |
        kubectl wait --for=condition=available \
          deployment/web-app -n staging --timeout=60s
        curl -f https://staging.example.com/health

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production    # Manuel onay gerektirir
    
    steps:
    - name: Configure kubectl
      uses: azure/k8s-set-context@v3
      with:
        method: kubeconfig
        kubeconfig: ${{ secrets.KUBECONFIG_PROD }}

    - name: Deploy to Production
      run: |
        IMAGE_TAG="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}"
        kubectl set image deployment/web-app \
          app=$IMAGE_TAG \
          -n production
        kubectl rollout status deployment/web-app -n production --timeout=10m
```

---

## Tekton — Kubernetes-Native CI/CD

Tekton, CI/CD iş akışlarını Kubernetes CRD'leri olarak çalıştırır.

```bash
# Tekton Pipeline kurulumu
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
```

### Task — Temel Birim

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: build-and-push
spec:
  params:
  - name: IMAGE
    type: string
  - name: CONTEXT
    type: string
    default: "."
  workspaces:
  - name: source
  steps:
  - name: build
    image: gcr.io/kaniko-project/executor:v1.23.0
    args:
    - --dockerfile=Dockerfile
    - --context=$(workspaces.source.path)/$(params.CONTEXT)
    - --destination=$(params.IMAGE)
    - --cache=true
    - --cache-ttl=24h
```

### Pipeline — Task Zinciri

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: ci-pipeline
spec:
  params:
  - name: repo-url
    type: string
  - name: image
    type: string
  workspaces:
  - name: shared-workspace

  tasks:
  - name: fetch-source
    taskRef:
      name: git-clone
    params:
    - name: url
      value: $(params.repo-url)
    workspaces:
    - name: output
      workspace: shared-workspace

  - name: run-tests
    taskRef:
      name: golang-test
    runAfter: [fetch-source]
    workspaces:
    - name: source
      workspace: shared-workspace

  - name: build-push
    taskRef:
      name: build-and-push
    runAfter: [run-tests]
    params:
    - name: IMAGE
      value: $(params.image)
    workspaces:
    - name: source
      workspace: shared-workspace

  - name: deploy
    taskRef:
      name: kubernetes-actions
    runAfter: [build-push]
    params:
    - name: script
      value: |
        kubectl set image deployment/web-app app=$(params.image)
        kubectl rollout status deployment/web-app --timeout=5m
```

### PipelineRun — Tetikleyici

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ci-run-
spec:
  pipelineRef:
    name: ci-pipeline
  params:
  - name: repo-url
    value: https://github.com/company/web-app
  - name: image
    value: ghcr.io/company/web-app:1.0.0
  workspaces:
  - name: shared-workspace
    volumeClaimTemplate:
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 1Gi
```

---

## GitOps ile CI/CD Entegrasyonu

```
[GitHub Actions]           [ArgoCD]
CI: Test + Build           CD: Deploy
     │                          │
     ▼                          │
Image Push →  Git Push →  ArgoCD Sync
(Registry)  (values.yaml    (K8s apply)
             image tag güncelle)
```

```yaml
# GitHub Actions'ta image tag'ini repo'ya yaz
- name: Update image tag in GitOps repo
  run: |
    git clone https://x-access-token:${{ secrets.GIT_TOKEN }}@github.com/company/gitops-repo
    cd gitops-repo
    
    # Helm values veya kustomize overlay güncelle
    sed -i "s|image:.*|image: ghcr.io/company/web-app:sha-${{ github.sha }}|" \
      apps/web-app/values.yaml
    
    git config user.email "ci@company.com"
    git config user.name "CI Bot"
    git add -A
    git commit -m "ci: update web-app to sha-${{ github.sha }}"
    git push
    # ArgoCD otomatik algılar ve sync eder
```

---

## Image Security Scanning (Pipeline'a Entegre)

```yaml
# GitHub Actions'ta Trivy
- name: Security Scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'    # CRITICAL/HIGH varsa pipeline başarısız

- name: Upload Trivy results to Security tab
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

---

## Best Practices

```yaml
# 1. Her deployment için resource limits zorunlu
# 2. Staging → Production → Manuel onay gerekli
# 3. Rollback otomasyonu:

- name: Rollback on Failure
  if: failure()
  run: |
    kubectl rollout undo deployment/web-app -n production
    kubectl rollout status deployment/web-app -n production --timeout=3m
```

> [!TIP]
> CI'da image build, CD'de deploy. İkisini ayırın. CI pipeline'ı hızlı olmalı (< 5 dakika), CD pipeline'ı güvenli olmalı (canary + smoke test + onay).

> [!WARNING]
> `latest` tag kullanmayın. Her image'ı git SHA veya semver ile etiketleyin. Aksi takdirde hangi kodun deploy edildiğini takip edemezsiniz.
