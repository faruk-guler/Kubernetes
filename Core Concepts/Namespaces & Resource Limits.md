# Namespace & Resource Limits

Namespace, Kubernetes cluster'ını mantıksal bölümlere ayırır. ResourceQuota ve LimitRange ile her namespace'in ne kadar kaynak kullanabileceği kontrol edilir.

---

## Namespace

```bash
# Namespace oluştur
kubectl create namespace team-alpha
kubectl create namespace team-beta

# Varsayılan namespace'ler
kubectl get namespaces
# default       → namespace belirtilmeden oluşturulan kaynaklar
# kube-system   → K8s sistem bileşenleri (DNS, scheduler vb.)
# kube-public   → Herkese açık kaynaklar
# kube-node-lease → Node heartbeat'leri

# Namespace bazlı çalışma
kubectl get pods -n team-alpha
kubectl config set-context --current --namespace=team-alpha   # Varsayılan ayarla

# Namespace sil (içindeki tüm kaynakları da siler!)
kubectl delete namespace team-alpha
```

---

## ResourceQuota — Namespace Kaynak Sınırı

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    # Compute
    requests.cpu: "10"           # Toplam CPU request
    requests.memory: "20Gi"      # Toplam Memory request
    limits.cpu: "20"             # Toplam CPU limit
    limits.memory: "40Gi"        # Toplam Memory limit

    # Object sayısı
    pods: "100"
    services: "20"
    persistentvolumeclaims: "30"
    secrets: "50"
    configmaps: "50"

    # LoadBalancer sayısı kısıtla
    services.loadbalancers: "3"
    services.nodeports: "0"      # NodePort yasak

    # Storage
    requests.storage: "500Gi"
    standard.storageclass.storage.k8s.io/requests.storage: "200Gi"
```

```bash
# Quota kullanımını kontrol et
kubectl describe resourcequota team-alpha-quota -n team-alpha
# Resource          Used   Hard
# --------          ----   ----
# limits.cpu        2500m  20
# limits.memory     4Gi    40Gi
# pods              8      100
```

---

## LimitRange — Pod Varsayılan ve Maksimum Limitleri

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: team-alpha-limits
  namespace: team-alpha
spec:
  limits:
  # Container sınırları
  - type: Container
    default:                # Limit belirtilmemişse bu değer atanır
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:         # Request belirtilmemişse bu değer atanır
      cpu: "100m"
      memory: "128Mi"
    max:                    # Üstü kabul edilmez
      cpu: "4"
      memory: "8Gi"
    min:                    # Altı kabul edilmez
      cpu: "50m"
      memory: "64Mi"

  # Pod toplam sınırı
  - type: Pod
    max:
      cpu: "8"
      memory: "16Gi"

  # PVC sınırı
  - type: PersistentVolumeClaim
    max:
      storage: 100Gi
    min:
      storage: 1Gi
```

---

## Namespace İzolasyon Stratejileri

### Ekip Bazlı İzolasyon

```yaml
# Her ekip için ayrı namespace + quota
# Ortak template
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-backend
  labels:
    team: backend
    environment: production
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
  namespace: team-backend
spec:
  hard:
    requests.cpu: "8"
    requests.memory: "16Gi"
    limits.cpu: "16"
    limits.memory: "32Gi"
    pods: "50"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: limits
  namespace: team-backend
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    default:
      cpu: "500m"
      memory: "256Mi"
    max:
      cpu: "2"
      memory: "4Gi"
```

### Ortam Bazlı İzolasyon

```bash
# dev / staging / production namespace'leri
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace production

# NetworkPolicy ile namespace izolasyonu
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
  namespace: production
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: {}       # Sadece aynı namespace'den
EOF
```

---

## Namespace Silme Takılması

```bash
# "Terminating" durumunda takılı namespace
kubectl get namespace stuck-ns -o json > stuck-ns.json

# finalizers alanını temizle
# "finalizers": [] yapın
kubectl replace --raw "/api/v1/namespaces/stuck-ns/finalize" \
  -f stuck-ns.json

# veya
kubectl patch namespace stuck-ns \
  -p '{"metadata":{"finalizers":[]}}' \
  --type=merge
```

---

## Quota Olmadan Çalışan Namespace Tespiti

```bash
# Quota tanımlanmamış namespace'ler
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get resourcequota -n $ns 2>/dev/null | wc -l)
  if [ "$count" -le 1 ]; then
    echo "⚠️  Quota yok: $ns"
  fi
done

# LimitRange olmayan namespace'ler
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get limitrange -n $ns 2>/dev/null | wc -l)
  if [ "$count" -le 1 ]; then
    echo "⚠️  LimitRange yok: $ns"
  fi
done
```

---

## RBAC ile Namespace Yetkilendirme

```yaml
# Ekip üyelerine sadece kendi namespace'lerinde yetki ver
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-dev
  namespace: team-alpha
subjects:
- kind: Group
  name: team-alpha-developers    # Azure AD / OIDC grup
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit                     # Built-in role: create/update/delete
  apiGroup: rbac.authorization.k8s.io
---
# Read-only erişim
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-viewer
  namespace: team-alpha
subjects:
- kind: Group
  name: team-alpha-ops
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

> [!TIP]
> Her production namespace'inde hem **ResourceQuota** hem **LimitRange** olmalı. LimitRange olmadan limit belirtilmemiş pod'lar namespace Quota'sını tamamen tüketebilir (limit=sonsuz gibi davranır).

> [!WARNING]
> `kube-system` namespace'ine ResourceQuota ekleme — sistem bileşenleri (CoreDNS, kube-proxy) kısıtlanırsa cluster bozulabilir.
