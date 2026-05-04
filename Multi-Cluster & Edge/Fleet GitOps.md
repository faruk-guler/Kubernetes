# Fleet — GitOps ile Çoklu Cluster Yönetimi

Rancher Fleet, yüzlerce Kubernetes cluster'ını tek bir Git deposundan GitOps prensibiyle yönetir. Her cluster, Git'teki tanımına otomatik olarak kendini senkronize eder.

---

## Fleet vs ArgoCD

| Özellik | Fleet | ArgoCD |
|:--------|:------|:-------|
| **Ölçek** | 1000+ cluster | 100-200 cluster (cluster başına) |
| **Mimari** | Hub-spoke (tek merkez) | Her cluster'da ArgoCD |
| **Kurulum** | Rancher entegreli | Bağımsız |
| **UI** | Rancher UI | Kendi UI |
| **Multi-tenancy** | GitRepo + Bundle | AppProject |
| **Hedef kitle** | Edge + büyük ölçek | Orta ölçek, gelişmiş GitOps |

---

## Mimari

```
[Fleet Manager - Management Cluster]
   │
   ├── GitRepo CRD → Git deposunu izler
   ├── Bundle CRD → Manifesti paketler
   └── BundleDeployment → Cluster'lara dağıtır

[Workload Cluster 1]   [Workload Cluster 2]   [Edge Device N]
   fleet-agent            fleet-agent            fleet-agent
   (pull & apply)         (pull & apply)         (pull & apply)
```

---

## Kurulum

```bash
# Fleet, Rancher ile otomatik gelir
# Standalone kurulum:
helm repo add fleet https://rancher.github.io/fleet-helm-charts/

# Fleet CRD'ler ve controller
helm install fleet-crd fleet/fleet-crd -n fleet-system --create-namespace
helm install fleet fleet/fleet -n fleet-system

# Fleet agent (workload cluster'lara)
helm install fleet-agent fleet/fleet-agent \
  -n fleet-system \
  --create-namespace \
  --set apiServerURL="https://management-cluster:6443" \
  --set apiServerCA="$(kubectl get secret -n fleet-system fleet-controller-bootstrap-token \
    -o jsonpath='{.data.ca\.crt}' | base64 -d)"
```

---

## GitRepo — Git Deposunu İzle

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: production-apps
  namespace: fleet-default
spec:
  repo: https://github.com/company/k8s-manifests
  branch: main
  paths:
  - apps/web-app
  - apps/api-service

  # Hedef: "production" etiketli tüm cluster'lar
  targets:
  - name: production
    clusterSelector:
      matchLabels:
        env: production

  # Özel ayarlar
  pollingInterval: 30s        # 30 saniyede bir kontrol
  clientSecretName: git-auth  # Private repo için

---
# Private repo kimlik bilgisi
apiVersion: v1
kind: Secret
metadata:
  name: git-auth
  namespace: fleet-default
type: kubernetes.io/basic-auth
stringData:
  username: git-user
  password: ghp_your_token
```

---

## Cluster Grupları

```yaml
# ClusterGroup — cluster'ları mantıksal grupla
apiVersion: fleet.cattle.io/v1alpha1
kind: ClusterGroup
metadata:
  name: eu-production
  namespace: fleet-default
spec:
  selector:
    matchLabels:
      region: eu
      env: production
```

```yaml
# GitRepo'yu ClusterGroup'a hedefle
spec:
  targets:
  - name: eu-prod
    clusterGroup: eu-production
  - name: asia-prod
    clusterSelector:
      matchLabels:
        region: asia
        env: production
```

---

## Cluster Bazında Override

Fleet'in güçlü özelliği: aynı Git deposundaki manifesti her cluster için özelleştir.

```
# Git repo yapısı:
apps/web-app/
├── deployment.yaml          ← Temel manifest
├── service.yaml
└── fleet.yaml               ← Fleet yapılandırması
    overlays/
    ├── production/
    │   └── deployment.yaml  ← Production override
    └── staging/
        └── deployment.yaml  ← Staging override
```

```yaml
# fleet.yaml — kustomize ile override
defaultNamespace: production
kustomize:
  dir: .

targetCustomizations:
- name: staging
  clusterSelector:
    matchLabels:
      env: staging
  kustomize:
    dir: overlays/staging

- name: production
  clusterSelector:
    matchLabels:
      env: production
  kustomize:
    dir: overlays/production
  helm:
    values:
      replicaCount: 5        # Production'da 5 replica
      resources:
        limits:
          memory: "1Gi"
```

---

## Helm Chart Dağıtımı

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: monitoring-stack
  namespace: fleet-default
spec:
  repo: https://github.com/company/fleet-configs
  branch: main
  paths:
  - charts/monitoring

  targets:
  - name: all-clusters
    clusterSelector:
      matchLabels:
        monitoring: enabled
```

```yaml
# charts/monitoring/fleet.yaml
helm:
  chart: kube-prometheus-stack
  repo: https://prometheus-community.github.io/helm-charts
  version: "56.0.0"
  releaseName: prometheus
  namespace: monitoring
  values:
    grafana:
      adminPassword: "SecurePass2026!"
    prometheus:
      prometheusSpec:
        retention: 30d

targetCustomizations:
- name: large-clusters
  clusterSelector:
    matchLabels:
      size: large
  helm:
    values:
      prometheus:
        prometheusSpec:
          resources:
            requests:
              memory: "4Gi"
            limits:
              memory: "8Gi"
```

---

## Durum İzleme

```bash
# Fleet agent durumu
kubectl get gitrepo -n fleet-default
# NAME              REPO                              COMMIT  BUNDLEDEPLOYMENTS  READY
# production-apps   https://github.com/company/...   abc123  5/5                True

# Bundle'lar
kubectl get bundle -n fleet-default

# Cluster'lara dağıtım durumu
kubectl get bundledeployment -A

# Belirli GitRepo'nun detayı
kubectl describe gitrepo production-apps -n fleet-default
```

---

## Edge Kullanım Senaryosu

```yaml
# 500 fabrika cihazını aynı Fleet ile yönet
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: factory-config
spec:
  repo: https://github.com/company/edge-configs
  branch: main
  paths:
  - factory/base

  targets:
  # Her fabrikaya özel config — label ile
  - name: factory-istanbul
    clusterSelector:
      matchLabels:
        location: istanbul
    helm:
      values:
        factoryId: "IST-001"
        timezone: "Europe/Istanbul"

  - name: factory-berlin
    clusterSelector:
      matchLabels:
        location: berlin
    helm:
      values:
        factoryId: "BER-042"
        timezone: "Europe/Berlin"
```

> [!TIP]
> Edge ortamlarında ağ kesintileri yaşanır. Fleet agent, bağlantı koptuğunda mevcut state'i korur, bağlantı gelince sync eder. Bu **offline-first** davranış edge için kritiktir.
