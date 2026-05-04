# Multi-Tenancy Patterns

Kubernetes'te birden fazla ekip, uygulama veya müşteriyi aynı cluster üzerinde güvenli ve izole biçimde barındırma mimarileri.

---

## Soft vs Hard Multi-Tenancy

```
Soft Tenancy (Namespace bazlı):
  Aynı cluster, aynı control plane
  Namespace + RBAC + NetworkPolicy + ResourceQuota
  Yeterli: İç ekipler, güvenen partnerler
  Risk: Hata yapan tenant → diğerini etkiler (noisy neighbor)

Hard Tenancy (Cluster bazlı):
  Her tenant → ayrı cluster veya vCluster
  Tam izolasyon
  Yeterli: Farklı müşteriler, compliance gereksinimleri
  Maliyet: Yüksek
```

---

## Model 1: Namespace Bazlı İzolasyon

```yaml
# Her ekip için izole namespace seti
namespaces:
  - team-alpha-dev
  - team-alpha-staging
  - team-alpha-prod
  - team-beta-dev
  - team-beta-prod

# Her namespace için:
# 1. ResourceQuota — kaynak sınırı
# 2. LimitRange — varsayılan limitler
# 3. RBAC — sadece kendi namespace'ini görsün
# 4. NetworkPolicy — namespace arası trafik kısıtla
```

```yaml
# 1. ResourceQuota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha-prod
spec:
  hard:
    requests.cpu: "20"
    requests.memory: "40Gi"
    limits.cpu: "40"
    limits.memory: "80Gi"
    pods: "100"
    services.loadbalancers: "3"
    persistentvolumeclaims: "20"
---
# 2. LimitRange — varsayılan limitler
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-alpha-prod
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "64Mi"
---
# 3. NetworkPolicy — namespace izolasyonu
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: team-alpha-prod
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector: {}              # Sadece aynı namespace'den
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: team-alpha-prod
  - from:
    - namespaceSelector:
        matchLabels:
          role: ingress            # Ingress controller izin
  egress:
  - to:
    - podSelector: {}
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system   # DNS
    ports:
    - port: 53
```

---

## Model 2: Hierarchical Namespace Controller (HNC)

```bash
# HNC kurulumu
kubectl apply -f https://github.com/kubernetes-sigs/hierarchical-namespaces/releases/latest/download/default.yaml

# HNC kubectl plugin
kubectl krew install hns
```

```yaml
# Parent namespace oluştur
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: team-alpha
spec:
  parent: ""    # Kök namespace

# Alt namespace'ler parent'tan RBAC/NetworkPolicy miras alır
```

```bash
# Alt namespace oluştur
kubectl hns create team-alpha-dev -n team-alpha
kubectl hns create team-alpha-prod -n team-alpha

# Hiyerarşiyi gör
kubectl hns tree team-alpha
# team-alpha
# ├── team-alpha-dev
# └── team-alpha-prod

# Parent'taki RBAC otomatik alt namespace'lere propagate edilir
```

---

## Model 3: vCluster (Virtual Cluster)

```bash
# Her tenant için izole sanal cluster
vcluster create tenant-company-a \
  --namespace vcluster-company-a \
  --create-namespace

# Tenant kendi admin'ine kubeconfig verir
vcluster connect tenant-company-a \
  -n vcluster-company-a > tenant-a.kubeconfig

# Tenant artık kendi "cluster"ında çalışır
kubectl --kubeconfig=tenant-a.kubeconfig get nodes
```


---

## Model 4: Karpenter Node Pool Ayrımı

```yaml
# Her ekip farklı node pool'da çalışır
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: team-alpha-pool
spec:
  template:
    metadata:
      labels:
        team: alpha
    spec:
      taints:
      - key: team
        value: alpha
        effect: NoSchedule
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
```

```yaml
# Team Alpha pod'ları kendi node'larında çalışır
spec:
  tolerations:
  - key: team
    value: alpha
    effect: NoSchedule
  nodeSelector:
    team: alpha
```

---

## RBAC Tenant İzolasyonu

```yaml
# Tenant admin — sadece kendi namespace'ini yönetir
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-admin
  namespace: team-alpha-prod
subjects:
- kind: Group
  name: team-alpha                    # IdP'den gelen grup
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin                         # Namespace kapsamlı admin
  apiGroup: rbac.authorization.k8s.io
---
# Başka namespace'leri göremesin
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: namespace-viewer-own-only
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]
  resourceNames: ["team-alpha-prod", "team-alpha-dev"]
```

---

## Kyverno ile Tenant Politikaları

```yaml
# Tenant'lar sadece kendi label'ı ile kaynak oluşturabilir
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-team-label
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-team-label
    match:
      resources:
        kinds: [Pod, Deployment, Service]
    validate:
      message: "team label zorunlu"
      pattern:
        metadata:
          labels:
            team: "?*"
---
# Namespace dışına PVC isteyemez
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: restrict-storageclass
  namespace: team-alpha-prod
spec:
  rules:
  - name: check-storageclass
    match:
      resources:
        kinds: [PersistentVolumeClaim]
    validate:
      message: "Sadece 'standard' StorageClass kullanılabilir"
      pattern:
        spec:
          storageClassName: standard
```

---

## Hangi Model Ne Zaman?

| Senaryo | Önerilen Model |
|:--------|:--------------|
| İç ekipler (güvenen) | Namespace + RBAC + Quota |
| Ekip hiyerarşisi | HNC (Hierarchical Namespace) |
| Farklı müşteriler (SaaS) | vCluster (hard isolation) |
| Maliyet izolasyonu | Node Pool (Karpenter) |
| Compliance (PCI, HIPAA) | Ayrı fiziksel cluster |
