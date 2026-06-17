# Helm — Kubernetes Paket Yöneticisi

## 📦 Kubernetes'in Lojistik Generali: Neden Helm?

Kubernetes üzerinde bir mikroservis mimarisi ayağa kaldırmak; bir ordu dolusu askere (Pod'lar, Deployment'lar, Service'ler, Ingress'ler, PVC'ler, Secret'lar) tek tek nerede duracaklarını ve ne yapacaklarını bildirmek gibidir. Her bir servis için ayrı ayrı düzinelerce YAML dosyası yazmak, bunları yönetmek ve doğru sırayla cluster'a göndermek zamanla tam bir yönetim kabusuna dönüşür.

İşte **Helm**, tüm bu askeri birliği tek bir komutla ayağa kaldırıp yöneten, onları "Chart" adı verilen standart kargo paketleri halinde gruplayan, Kubernetes'in kıdemli paketleme ve dağıtım yöneticisidir.

---

## Helm Nedir?

Helm, Kubernetes için `apt` veya `yum` gibi bir paket yöneticisidir. Karmaşık uygulamaları (Prometheus, ArgoCD, cert-manager) tek komutla kurup güncellemenizi sağlar.

```bash
# Helm kurulumu
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

> [!WARNING]
> İnternetten doğrudan script indirip çalıştırmak (`curl | bash` yöntemi) güvenlik riskleri barındırır. Üretim (production) ortamlarında resmi binary paketlerini doğrulamayı veya sistem paket yöneticilerini (`apt`, `brew`, `dnf` vb.) kullanmayı tercih edin.

## Temel Helm Komutları

```bash
# Repo yönetimi
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update                          # Tüm repoları güncelle

# Chart aramak
helm search repo postgresql
helm search hub nginx                     # Artifact Hub'da ara

# Kurulum
helm install my-release bitnami/nginx \
  --namespace my-namespace \
  --create-namespace \
  --values values.yaml

# Listeleme ve durum
helm list -A                              # Tüm namespace'ler
helm status my-release -n my-namespace

# Güncelleme
helm upgrade my-release bitnami/nginx --values values.yaml

# Geri alma
helm rollback my-release 1

# Kaldırma
helm uninstall my-release -n my-namespace
```

## values.yaml ile Özelleştirme

```bash
# Varsayılan değerleri gör
helm show values bitnami/nginx > default-values.yaml

# Özelleştirilmiş kurulum
cat <<EOF > my-values.yaml
replicaCount: 3
service:
  type: ClusterIP
ingress:
  enabled: false
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
EOF

helm install nginx bitnami/nginx -f my-values.yaml
```

## Kendi Chart'ınızı Oluşturun

```bash
# Yeni chart iskeleti oluştur
helm create my-app

# Yapı:
# my-app/
# ├── Chart.yaml
# ├── values.yaml
# ├── templates/
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   └── _helpers.tpl
# └── charts/           (bağımlılıklar)

# Chart doğrulama
helm lint my-app/

# Template çıktısını gör (kurulum yapmadan)
helm template my-app my-app/ --values custom-values.yaml

# Paketleme
helm package my-app/
```

## OCI Registry (2026 Standardı)

2026'da Helm chart'ları OCI Registry üzerinden dağıtılır:

```bash
# OCI chart çekme
helm pull oci://ghcr.io/cert-manager/charts/cert-manager --version v1.16.0

# OCI chart kurulumu
helm install cert-manager oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true
```

## ArgoCD ile Helm Entegrasyonu

ArgoCD, Helm chart'larını doğrudan destekler:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: "58.x"
    helm:
      valuesObject:
        alertmanager:
          enabled: true
        grafana:
          adminPassword: "changeme"
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

> [!TIP]
> ArgoCD üzerinden Helm kurulumu yapıldığında Helm release'ini `helm list` ile göremezsiniz — ArgoCD kendi state mekanizmasını kullanır. `kubectl get application -n argocd` ile durumu takip edin.
