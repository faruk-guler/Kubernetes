# vCluster — Sanal Kubernetes Cluster'ları

vCluster, fiziksel bir Kubernetes cluster üzerinde tamamen izole sanal cluster'lar oluşturur. Her sanal cluster kendi API Server'ına ve kendi iş yüklerine sahiptir.

---

## Neden vCluster?

```
Ana Cluster (Host)
  ├── vCluster: Dev    ← Paylaşımlı node'lar, pod olarak çalışır
  ├── vCluster: Test   ← Paylaşımlı node'lar
  └── vCluster: Team-Alpha  ← Kendi namespace dünyası
```

**Kullanım:** CI/CD per-PR izole cluster, multi-tenant ekipler, eğitim ortamları.

---

## Kurulum & Kullanım

```bash
curl -L -o vcluster https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64
chmod +x vcluster && mv vcluster /usr/local/bin/

# vCluster oluştur
vcluster create team-alpha --namespace vcluster-team-alpha --create-namespace

# Bağlan
vcluster connect team-alpha -n vcluster-team-alpha
kubectl get nodes    # Host node'ları sanal olarak görünür
kubectl get ns       # Temiz namespace listesi
```

---

## Yapılandırma (values.yaml)

```yaml
sync:
  nodes:
    enabled: true
  persistentvolumes:
    enabled: true
  ingresses:
    enabled: true       # Ingress objelerini host'a geçir

resources:
  limits:
    cpu: "2"
    memory: "2Gi"

isolation:
  enabled: true
  networkPolicy:
    enabled: true
  podSecurityStandard: restricted
```

```bash
vcluster create team-alpha \
  --namespace vcluster-team-alpha \
  --create-namespace \
  --values vcluster-values.yaml
```

---

## GitOps ile vCluster (ArgoCD)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vcluster-team-alpha
  namespace: argocd
spec:
  source:
    repoURL: https://charts.loft.sh
    chart: vcluster
    targetRevision: 0.20.0
    helm:
      releaseName: team-alpha
      values: |
        sync:
          ingresses:
            enabled: true
        isolation:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: vcluster-team-alpha
  syncPolicy:
    automated:
      prune: true
    syncOptions:
    - CreateNamespace=true
```

---

## CI/CD: PR Başına Geçici vCluster

```yaml
# GitHub Actions — Her PR için izole test ortamı
- name: Create ephemeral vCluster
  run: |
    vcluster create pr-${{ github.event.pull_request.number }} \
      --namespace pr-${{ github.event.pull_request.number }} \
      --create-namespace

- name: Connect & Test
  run: |
    vcluster connect pr-${{ github.event.pull_request.number }} \
      -n pr-${{ github.event.pull_request.number }} \
      --kube-config-context-name pr-cluster
    kubectl --context=pr-cluster apply -f k8s/
    pytest tests/integration/

- name: Cleanup
  if: always()
  run: |
    vcluster delete pr-${{ github.event.pull_request.number }} \
      -n pr-${{ github.event.pull_request.number }}
```

---

## Yönetim Komutları

```bash
vcluster list                              # Tüm vCluster'lar
vcluster pause team-alpha -n vcluster-...  # Duraklat (maliyet tasarrufu)
vcluster resume team-alpha -n vcluster-... # Devam ettir
vcluster delete team-alpha -n vcluster-... # Sil
```

---

## Karşılaştırma

| Özellik | Namespace | vCluster | Fiziksel Cluster |
|:--------|:----------|:---------|:-----------------|
| İzolasyon | Zayıf | **Güçlü** | Tam |
| Maliyet | Düşük | **Düşük** | Yüksek |
| Kendi API Server | ❌ | **✅** | ✅ |
| Kendi CRD/RBAC | ❌ | **✅** | ✅ |
| Kurulum | Saniye | **30 saniye** | Dakikalar |
