# CI/CD Pipeline Geçişi

Mevcut CI/CD altyapısını (Jenkins, GitLab CI, GitHub Actions) Kubernetes ile entegre etmek veya tamamen Kubernetes-native pipeline'lara taşımak.

---

## Geçiş Önce: Mevcut Durum Analizi

```
Soru                                     | Hayır | Evet
-----------------------------------------|-------|-----
CI sunucusu VM'de mi çalışıyor?          |       |
Build agent'ları statik mi?              |       |
Build süresi 10+ dakika mı?             |       |
Paralel build limiti var mı?            |       |
Build environment tutarsız mı?          |       |
Artifact depolama manuel mi?            |       |

3+ "Evet" → Kubernetes CI/CD ciddi iyileştirme sağlar
```

---

## Jenkins → Kubernetes Entegrasyonu

### Jenkins Kubernetes Plugin

```groovy
// Jenkinsfile — Pod template ile dinamik agent
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: maven
    image: maven:3.9-eclipse-temurin-21
    command: [cat]
    tty: true
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "4"
        memory: "4Gi"
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command: [cat]
    tty: true
    volumeMounts:
    - name: kaniko-secret
      mountPath: /kaniko/.docker
  volumes:
  - name: kaniko-secret
    secret:
      secretName: regcred
      items:
      - key: .dockerconfigjson
        path: config.json
"""
        }
    }
    stages {
        stage('Build') {
            steps {
                container('maven') {
                    sh 'mvn package -DskipTests'
                }
            }
        }
        stage('Build Image') {
            steps {
                container('kaniko') {
                    sh """
                        /kaniko/executor \
                          --context=\${WORKSPACE} \
                          --dockerfile=Dockerfile \
                          --destination=ghcr.io/company/my-app:\${BUILD_NUMBER} \
                          --cache=true
                    """
                }
            }
        }
        stage('Deploy to Staging') {
            steps {
                container('maven') {
                    sh """
                        kubectl set image deployment/my-app \
                          app=ghcr.io/company/my-app:\${BUILD_NUMBER} \
                          -n staging
                        kubectl rollout status deployment/my-app -n staging
                    """
                }
            }
        }
    }
}
```

### Jenkins on Kubernetes (Helm)

```bash
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins \
  --namespace ci \
  --create-namespace \
  --set controller.serviceType=ClusterIP \
  --set controller.resources.requests.cpu=500m \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=2 \
  --set controller.resources.limits.memory=4Gi \
  --set persistence.size=20Gi \
  --set persistence.storageClass=longhorn
```

---

## GitLab CI → Kubernetes Runner

```yaml
# .gitlab-ci.yml — Kubernetes executor ile
variables:
  DOCKER_HOST: tcp://docker:2376
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

stages:
  - test
  - build
  - deploy

test:
  stage: test
  image: python:3.12-slim
  script:
    - pip install -r requirements.txt
    - pytest tests/ --junitxml=report.xml
  artifacts:
    reports:
      junit: report.xml
  tags:
    - kubernetes    # K8s runner kullan

build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:debug
    entrypoint: [""]
  script:
    - /kaniko/executor
        --context "$CI_PROJECT_DIR"
        --dockerfile "$CI_PROJECT_DIR/Dockerfile"
        --destination "$IMAGE"
        --cache=true
  tags:
    - kubernetes

deploy-staging:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: staging
    url: https://staging.company.com
  script:
    - kubectl set image deployment/my-app app=$IMAGE -n staging
    - kubectl rollout status deployment/my-app -n staging
  only:
    - main
  tags:
    - kubernetes

deploy-production:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: production
    url: https://app.company.com
  script:
    - kubectl set image deployment/my-app app=$IMAGE -n production
    - kubectl rollout status deployment/my-app -n production
  when: manual    # Manuel onay
  only:
    - tags
  tags:
    - kubernetes
```

### GitLab Runner Kubernetes Kurulumu

```bash
helm repo add gitlab https://charts.gitlab.io
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace ci \
  --set gitlabUrl=https://gitlab.company.com \
  --set runnerRegistrationToken=<token> \
  --set rbac.create=true \
  --set runners.executor=kubernetes \
  --set runners.kubernetes.namespace=ci \
  --set runners.kubernetes.cpu_request=100m \
  --set runners.kubernetes.memory_request=128Mi \
  --set runners.kubernetes.cpu_limit=2 \
  --set runners.kubernetes.memory_limit=2Gi
```

---

## GitOps Tabanlı CD (Önerilen)

Jenkins/GitLab CI build yapar, ArgoCD deploy eder:

```
Geliştirici → Git Push
     ↓
CI Pipeline (Jenkins/GitLab/GitHub Actions):
  1. Test
  2. Build image
  3. Push to registry
  4. GitOps repo'daki image tag'ini güncelle
     (helm values.yaml veya kustomize overlay)
     ↓
ArgoCD (Sürekli izler):
  5. GitOps repo değişikliğini algılar
  6. Cluster'ı Git'e sync eder
  7. Deployment tamamlandı
```

```bash
# CI'da GitOps repo güncelleme
update_image_tag() {
  git clone https://oauth2:${GITOPS_TOKEN}@gitlab.company.com/company/gitops-repo
  cd gitops-repo

  # Helm values güncelle
  yq e ".image.tag = \"${IMAGE_TAG}\"" \
    -i apps/my-app/values.yaml

  git config user.email "ci@company.com"
  git config user.name "CI Bot"
  git add -A
  git commit -m "ci: bump my-app to ${IMAGE_TAG} [skip ci]"
  git push origin main
}
```

---

## Tekton: Kubernetes-Native Pipeline

```yaml
# CI/CD pipeline tamamen Kubernetes objesi olarak
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: full-pipeline
spec:
  params:
  - name: git-url
  - name: image
  workspaces:
  - name: workspace

  tasks:
  - name: git-clone
    taskRef: {name: git-clone, kind: ClusterTask}
    params:
    - {name: url, value: $(params.git-url)}
    workspaces:
    - {name: output, workspace: workspace}

  - name: unit-test
    taskRef: {name: golang-test, kind: ClusterTask}
    runAfter: [git-clone]
    workspaces:
    - {name: source, workspace: workspace}

  - name: build-push
    taskRef: {name: kaniko, kind: ClusterTask}
    runAfter: [unit-test]
    params:
    - {name: IMAGE, value: $(params.image)}
    workspaces:
    - {name: source, workspace: workspace}

  - name: deploy
    taskRef: {name: kubernetes-actions, kind: ClusterTask}
    runAfter: [build-push]
    params:
    - name: script
      value: |
        kubectl set image deployment/my-app \
          app=$(params.image) -n staging
        kubectl rollout status deployment/my-app -n staging
```

---

## Geçiş Adımları (Pratik)

```
Hafta 1-2: Hazırlık
  □ Kubernetes cluster'da CI namespace oluştur
  □ Docker registry hazırla (GHCR/GitLab Registry/Harbor)
  □ RBAC: CI service account'u oluştur (sınırlı yetkiyle)

Hafta 3-4: İlk Pipeline
  □ Bir servis seç (kritik olmayan)
  □ Mevcut pipeline'ı K8s agent'a taşı
  □ Kaniko ile K8s içinden image build
  □ Staging'e otomatik deploy ekle

Ay 2: Olgunlaştırma
  □ GitOps entegrasyonu (ArgoCD)
  □ Güvenlik: Trivy scan, Cosign sign
  □ Production için manuel onay
  □ Rollback mekanizması

Ay 3+: Standartlaştırma
  □ Tüm servisleri aynı pipeline template'e taşı
  □ Shared library (Jenkins) veya reusable workflow (GitHub Actions)
  □ Pipeline metrikleri (build süresi, başarı oranı)
```

> [!TIP]
> Geçişi aşamalı yapın. İlk servis başarılı olduktan sonra diğerlerini taşıyın. "Big bang" geçiş risklidir — bir servis bozulursa tüm ekip etkilenir.
