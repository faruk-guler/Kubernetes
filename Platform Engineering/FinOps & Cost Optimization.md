# FinOps & Kubernetes Maliyet Optimizasyonu

Kubernetes'te kaynaklar kolayca israf edilir. Yanlış ayarlanmış `requests/limits`, boşta çalışan node'lar ve unutulmuş namespace'ler sessizce para yakar. FinOps, bu israfı görünür kılıp optimize eder.

---

## Maliyet Görünürlüğü: Kubecost

Kubecost, Kubernetes kaynak kullanımını maliyet olarak gösterir.

```bash
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/
helm install kubecost cost-analyzer/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="your-token" \
  --set prometheus.server.persistentVolume.storageClass=longhorn

kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090
```

### Kubecost Önemli Görünümler

```bash
# Namespace bazında maliyet (son 30 gün)
# UI: Cost Allocation → Namespace

# Atıl (idle) kaynaklar
# UI: Savings → Idle Resources

# Maliyet tahminleri
# UI: Assets → Cluster
```

---

## Kaynak İsrafı Tespiti

### 1. Aşırı Sağlanan (Over-provisioned) Pod'lar

```bash
# CPU isteği vs gerçek kullanım
kubectl top pods -A --sort-by=cpu | head -20

# PromQL: Request vs Actual fark (israf oranı)
# CPU israfı
(
  sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace, pod)
  -
  sum(rate(container_cpu_usage_seconds_total{container!=""}[1h])) by (namespace, pod)
) > 0.5    # 0.5 core'dan fazla israf

# Bellek israfı
(
  sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace, pod)
  -
  sum(container_memory_working_set_bytes{container!=""}) by (namespace, pod)
) / 1024 / 1024 / 1024 > 1    # 1GB'dan fazla israf
```

### 2. Atıl Namespace'ler

```bash
# Son 7 gündür hiç pod çalışmamış namespace'ler
kubectl get pods -A --field-selector=status.phase=Running | awk '{print $1}' | sort -u > active_ns.txt
kubectl get ns | awk '{print $1}' | sort > all_ns.txt
comm -23 all_ns.txt active_ns.txt   # Atıl namespace'ler
```

### 3. Sahipsiz PVC'ler

```bash
# Bağlı pod'u olmayan PVC'ler (para ödeniyor ama kullanılmıyor)
kubectl get pvc -A | grep -v Bound
kubectl get pvc -A -o json | jq '.items[] | select(.status.phase=="Bound") |
  select(.metadata.annotations."volume.kubernetes.io/selected-node" == null) |
  {name: .metadata.name, namespace: .metadata.namespace, size: .spec.resources.requests.storage}'
```

---

## Maliyet Optimizasyon Stratejileri

### Strateji 1: VPA ile Otomatik Right-Sizing

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web-app-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  updatePolicy:
    updateMode: "Off"    # Önce "Off" ile tavsiye al, sonra "Auto" yap
  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: "50m"
        memory: "64Mi"
      maxAllowed:
        cpu: "2"
        memory: "2Gi"
```

```bash
# VPA tavsiyelerini gör (updateMode: Off ile)
kubectl describe vpa web-app-vpa -n production | grep -A 20 "Recommendation:"
# Lower Bound: cpu: 50m,  memory: 128Mi
# Target:      cpu: 200m, memory: 256Mi   ← Bunu requests olarak kullan
# Upper Bound: cpu: 1,    memory: 1Gi
```

### Strateji 2: Spot/Preemptible Node'lar

```yaml
# AWS Spot instance node pool
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: spot-workers
spec:
  requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["spot", "on-demand"]   # Spot önce dene, yoksa on-demand
  - key: node.kubernetes.io/instance-type
    operator: In
    values: ["m5.large", "m5.xlarge", "m4.large", "m4.xlarge"]

  # Batch ve stateless iş yükleri için
  taints:
  - key: spot
    value: "true"
    effect: NoSchedule

  limits:
    resources:
      cpu: "1000"
      memory: "4000Gi"
```

```yaml
# Spot toleration olan pod'lar
spec:
  tolerations:
  - key: spot
    operator: Equal
    value: "true"
    effect: NoSchedule
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot"]
```

### Strateji 3: Namespace Kaynak Kotaları

```yaml
# Her ekip için bütçe tanımla
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "20"        # Toplam CPU request limiti
    requests.memory: "40Gi"   # Toplam bellek request limiti
    limits.cpu: "40"
    limits.memory: "80Gi"
    persistentvolumeclaims: "20"
    requests.storage: "500Gi"
    count/pods: "100"
```

### Strateji 4: Scale-to-Zero (KEDA)

```yaml
# Gece saatlerinde pod'ları sıfıra indir
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: web-app-scaled
  namespace: staging
spec:
  scaleTargetRef:
    name: web-app
  minReplicaCount: 0       # Sıfıra kadar inebilir (staging için)
  maxReplicaCount: 10
  triggers:
  - type: cron
    metadata:
      timezone: "Europe/Istanbul"
      start: "08 09 * * 1-5"    # Pazartesi-Cuma 09:08'de başlat
      end: "00 19 * * 1-5"      # 19:00'da durdur
      desiredReplicas: "3"
```

### Strateji 5: Karpenter ile Akıllı Node Seçimi

```yaml
# Karpenter NodePool — en ucuz uygun node'u seç
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: cost-optimized
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot"]
      - key: karpenter.io/instance-category
        operator: In
        values: ["c", "m", "r"]    # Compute, Memory, General
  disruption:
    consolidationPolicy: WhenUnderutilized   # Boş node'ları sil
    consolidateAfter: 30s
  limits:
    cpu: 1000
```

---

## FinOps Dashboard (Grafana)

```promql
# Namespace başına aylık tahmini maliyet (CPU bazlı)
# CPU fiyatı: $0.048/core/saat (us-east-1 m5.large)
sum(
  kube_pod_container_resource_requests{resource="cpu"}
) by (namespace) * 0.048 * 24 * 30

# Atıl CPU maliyeti
(
  sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
  - sum(rate(container_cpu_usage_seconds_total[24h])) by (namespace)
) * 0.048 * 24 * 30

# Node kullanım verimliliği
sum(rate(container_cpu_usage_seconds_total{container!=""}[1h])) /
sum(kube_node_status_allocatable{resource="cpu"})
```

---

## FinOps Maturity Model

| Seviye | Pratik | Hedef |
|:------|:-------|:------|
| **Crawl** | Kubecost kur, maliyet göster | Görünürlük |
| **Walk** | Tag politikası, namespace quota | Sorumluluk |
| **Run** | VPA + Karpenter + Spot | Otomatik optimizasyon |
| **Fly** | Chargeback, FinOps KPI'ları | Maliyet kültürü |

> [!TIP]
> **Chargeback**: Her ekibin kendi Kubernetes maliyetini görmesi, sorumluluk duygusunu artırır. Kubecost'un "Shared Cost Allocation" özelliği ile ortak namespace maliyetleri (monitoring, ingress) ekiplere orantılı dağıtılabilir.
