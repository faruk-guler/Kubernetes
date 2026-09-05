# CI/CD Boru Hattı Kalıpları (CI/CD Pipeline Patterns)

Kubernetes ile entegre çalışan CI/CD (Sürekli Entegrasyon / Sürekli Dağıtım) boru hatları, "kod commit edildiği an testlerin çalışması, imajın derlenmesi ve güvenli bir şekilde kümeye deploy edilmesi" sürecini uçtan uca otomatikleştirir. Bu dokümanda; modern CI/CD olgunluk seviyelerini, GitHub Actions entegrasyonunu, Kubernetes-native çalışan **Tekton** mimarisini ve GitOps entegrasyon pratiklerini inceleyeceğiz.

---

## 1. CI/CD Olgunluk Seviyeleri

| Seviye | Dağıtım Tarzı | Risk Seviyesi |
| :---: | :--- | :--- |
| **Seviye 0** | Manuel Dağıtım (`kubectl apply -f` terminalden). | 🔴 Çok Yüksek |
| **Seviye 1** | Script Tabanlı Dağıtım (CI sunucusu ssh ile bağlanıp kubectl çalıştırır). | 🔴 Yüksek |
| **Seviye 2** | Otomatik Boru Hattı (Derleme, test, push ve deploy adımları CI ile yapılır). | 🟡 Orta |
| **Seviye 3** | GitOps Mimarisi (CI sadece imaj üretir ve Git'i günceller, CD/ArgoCD senkronize eder). | 🟢 Düşük |
| **Seviye 4** | Progresif Teslimat (Canary deploy, metrik denetimleri ve otomatik rollback). | 🟢 En Güvenli |

---

## 2. GitHub Actions ile Kubernetes Dağıtımı (Seviye 2 Model)

Aşağıdaki iş akışı (workflow), bir kodu derleyip doğrudan bir Kubernetes kümesine `kubeconfig` kullanarak deploy eden temel yapıyı gösterir:

```yaml
name: CI/CD Level 2
on:
  push:
    branches: [ "main" ]
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Build and Push Image
      run: |
        docker build -t my-app:${{ github.sha }} .
        docker push my-app:${{ github.sha }}
    - name: Set Kubernetes Context
      uses: azure/k8s-set-context@v3
      with:
        kubeconfig: ${{ secrets.KUBECONFIG }}
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/my-app my-app=my-app:${{ github.sha }}
        kubectl rollout status deployment/my-app
```

---

## 3. Tekton: Kubernetes-Native CI/CD Aracı

**Tekton**, CI/CD iş akışlarını Kubernetes podları ve CRD nesneleri olarak çalıştıran Kubernetes-native bir boru hattı motorudur.

### Kurulum

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
```

### A. Task (Temel Çalışma Birimi)

Tekton'da her adım (`Step`), tek bir pod içinde çalışan bir konteynerdir. Bu adımların birleşimi ise `Task` CRD'sini oluşturur.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: build-app
spec:
  steps:
    - name: build
      image: gcr.io/kaniko-project/executor:latest
      args:
        - "--dockerfile=Dockerfile"
        - "--destination=registry.company.com/my-app:latest"
```

### B. Pipeline (Task Zinciri)

Birden fazla Task'ı belirli bir sıra ve bağımlılıkla birbirine bağlayan yapı:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-and-deploy-pipeline
spec:
  tasks:
    - name: build-app-task
      taskRef:
        name: build-app
    - name: deploy-app-task
      taskRef:
        name: deploy-app
      runAfter:
        - build-app-task
```

### C. PipelineRun (Tetikleyici)

Yazılan bir Pipeline'ı fiilen çalıştırmak ve parametre göndermek için kullanılan nesnedir:

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: build-and-deploy-run-
spec:
  pipelineRef:
    name: build-and-deploy-pipeline
```

---

## 4. GitOps ile CI/CD Entegrasyon Kalıbı (Seviye 3)

Modern GitOps sistemlerinde CI ve CD süreçleri kesin çizgilerle birbirinden ayrılmıştır:

```text
[ Geliştirici Kod Push ]
          │
          ▼
┌──────────────────┐
│   CI (Github)    │ ──► (İmaj Derle, Tara ve Push Et)
└────────┬─────────┘
         │
         ▼ (Otomatik Git Commit & Push)
┌──────────────────┐
│   GitOps Repo    │ ──► (YAML dosyasındaki image tag'ini güncelle)
└────────┬─────────┘
         │
         ▼ (Pull & Sync)
┌──────────────────┐
│   CD (ArgoCD)    │ ──► (Kümeye uygula)
└──────────────────┘
```

### GitHub Actions Üzerinden GitOps Reposunu Otomatik Güncelleme Adımı

CI süreci başarıyla tamamlanıp yeni Docker imajı registry'ye push edildikten sonra, GitOps deposundaki imaj versiyonu otomatik güncellenir:

```yaml
    - name: Checkout GitOps Repository
      uses: actions/checkout@v4
      with:
        repository: company/gitops-manifests
        token: ${{ secrets.GITOPS_DEPLOY_PAT }}
        path: gitops-repo

    - name: Update Image Tag in GitOps Manifest
      run: |
        cd gitops-repo/environments/prod
        yq eval '.spec.template.spec.containers[0].image = "registry.company.com/my-app:${{ github.sha }}"' -i deployment.yaml
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git add deployment.yaml
        git commit -m "chore(release): bump my-app image to ${{ github.sha }} [skip ci]"
        git push origin main
```

---

## 5. İmaj Güvenliği Taraması (Pipeline Entegrasyonu)

Boru hattı içinde derlenen imajlar, registry'e gönderilmeden hemen önce **Trivy** ile taranmalı ve kritik bir açık bulunduğunda pipeline derhal sonlandırılmalıdır:

```yaml
    - name: Run Trivy Vulnerability Scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: registry.company.com/my-app:${{ github.sha }}
        format: 'table'
        exit-code: '1' # Eşik değer aşılırsa build'i kır (hata verdir)
        ignore-unfixed: true
        severity: 'CRITICAL,HIGH'
```

---

## 6. En İyi Pratikler (Best Practices)

1. **CI ve CD'yi Ayırın:** CI sadece kod bütünlüğünü test etmeli, imaj üretmeli ve GitOps reposunu güncellemelidir. Kümeye doğrudan erişim yetkisi (kubectl yetkisi) CI sunucularına verilmemelidir.
2. **Sürüm Etiketleri:** Asla `latest` imaj etiketi kullanmayın. Her imajı Git commit SHA'sı veya SemVer (Semantik Sürüm) kurallarına göre etiketleyin.
3. **Hafif CI, Sıkı CD:** CI pipeline'ı geliştiriciye hızlı geri bildirim vermek için 5 dakikadan kısa sürmelidir. CD aşaması ise kademeli (canary) ve güvenli ilerlemelidir.
