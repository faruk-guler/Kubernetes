# CI/CD Boru Hattı (Pipeline) Geçişi ve Kubernetes Entegrasyonu

Geleneksel sanal makineler (VM) üzerinde çalışan statik derleme (build) sunucularını, Kubernetes üzerinde dinamik olarak ölçeklenen ve konteyner-yerli (container-native) çalışan modern bir CI/CD yapısına taşımak, kaynak verimliliğini ve hızını artırır.

Bu dokümanda, Jenkins ve GitLab CI gibi popüler araçların Kubernetes ile entegrasyonu, Kaniko ile küme içinde güvenli imaj derleme ve GitOps tabanlı sürekli dağıtım (CD) geçişi ele alınmıştır.

---

## 1. Jenkins'in Kubernetes ile Entegrasyonu

Jenkins'i Kubernetes üzerinde konumlandırarak, her derleme işlemi için dinamik ve izole podlar (build agents) oluşturabilirsiniz. İşlem bittiğinde bu podlar otomatik olarak yok edilir.

### Dinamik Pod Şablonlu Jenkinsfile (Pipeline)

```groovy
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
        cpu: "2"
        memory: "4Gi"
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command: [cat]
    tty: true
    volumeMounts:
    - name: registry-secret
      mountPath: /kaniko/.docker
  volumes:
  - name: registry-secret
    secret:
      secretName: regcred
      items:
      - key: .dockerconfigjson
        path: config.json
"""
        }
    }
    stages {
        stage('Derleme ve Test') {
            steps {
                container('maven') {
                    sh 'mvn clean package -DskipTests=true'
                }
            }
        }
        stage('İmaj Derleme (Kaniko)') {
            steps {
                container('kaniko') {
                    // Kaniko, Docker daemon'a (dind) ihtiyaç duymadan K8s içinde güvenli imaj derler
                    sh """
                        /kaniko/executor \
                          --context=\${WORKSPACE} \
                          --dockerfile=Dockerfile \
                          --destination=ghcr.io/company/billing-api:\${BUILD_NUMBER} \
                          --cache=true
                    """
                }
            }
        }
    }
}
```

---

## 2. GitLab CI Kubernetes Runner Kurulumu

GitLab CI işlerini Kubernetes üzerinde dinamik podlar halinde çalıştırmak için **GitLab Runner** Helm chart kullanılarak kurulabilir:

```bash
# 1. GitLab Helm deposunu ekleyin
helm repo add gitlab https://charts.gitlab.io
helm repo update

# 2. GitLab Runner'ı kurun ve kotaları tanımlayın
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace ci \
  --create-namespace \
  --set gitlabUrl=https://gitlab.company.com \
  --set runnerRegistrationToken=<your-registration-token> \
  --set rbac.create=true \
  --set runners.executor=kubernetes \
  --set runners.kubernetes.namespace=ci \
  --set runners.kubernetes.cpu_request=500m \
  --set runners.kubernetes.memory_request=512Mi \
  --set runners.kubernetes.cpu_limit=2 \
  --set runners.kubernetes.memory_limit=4Gi
```

---

## 3. GitOps Tabanlı Dağıtım (ArgoCD / Flux v2)

Geleneksel CI araçlarının doğrudan üretim (production) kümesine erişip `kubectl apply` yapması büyük bir güvenlik açığıdır. Bunun yerine **GitOps** mimarisi tercih edilmelidir:

```
[ GİTOPS ÇALIŞMA AKIŞI ]

Geliştirici ──► Kodu Push Et (Git)
                  │
                  ▼
              CI Pipeline (GitHub Actions / GitLab CI)
                  │
                  ├──► 1. Testleri Koştur
                  ├──► 2. İmajı Derle ve Registry'ye Gönder
                  └──► 3. GitOps Reposundaki YAML İmaj Sürümünü Güncelle (yq)
                                     │
                                     ▼
                                 Argo CD ──► Değişikliği Algılar ve Kümeyi Günceller
```

### CI Boru Hattı İçinden GitOps Deposunu Güncelleme Betiği

```bash
#!/bin/bash
set -e

# Git ayarlarını yapın
git config --global user.email "ci-bot@company.com"
git config --global user.name "CI Automation Bot"

# GitOps deposunu klonlayın
git clone https://oauth2:${GITOPS_TOKEN}@gitlab.company.com/devops/gitops-manifests.git
cd gitops-manifests

# yq aracı ile values.yaml dosyasındaki imaj etiketini güncelleyin
yq -i ".billing.image.tag = \"${IMAGE_TAG}\"" apps/billing-api/values.yaml

# Değişiklikleri GitOps deposuna gönderin
git add apps/billing-api/values.yaml
git commit -m "ci: bump billing-api image to version ${IMAGE_TAG} [skip ci]"
git push origin main
```

---

## 4. Adım Adım CI/CD Geçiş Planı

### Hafta 1 - 2: Altyapı ve Hazırlık

* Kubernetes kümesinde CI işleri için izole bir isim alanı (`ci` veya `gitlab-runner`) oluşturulması.
* Özel konteyner kayıt defteri (GitHub Packages, GitLab Registry veya Harbor) bağlantıları için `imagePullSecrets` veya IAM rollerinin yapılandırılması.
* CI araçlarının küme kaynaklarını aşırı tüketmesini engellemek için ResourceQuota tanımlanması.

### Hafta 3 - 4: İlk Pilot Boru Hattı

* Kritik olmayan pilot bir uygulamanın seçilmesi.
* Dinamik agent (pod) yapısına geçilerek Jenkinsfile veya `.gitlab-ci.yml` dosyasının güncellenmesi.
* İmaj derleme süreçlerinin Docker-in-Docker (dind) yerine **Kaniko** ile değiştirilmesi.

### Ay 2+: GitOps ve Güvenlik Entegrasyonu

* ArgoCD veya Flux v2 kurulumunun yapılması.
* Derleme sonrasında Trivy ile imaj taraması ve Cosign ile imaj imzalama (image signing) adımlarının eklenmesi.
* Hatalı dağıtımlarda otomatik geri dönüş (rollback) mekanizmalarının devreye alınması.
