# Cluster Autoscaler

HPA ve VPA pod'ları ölçeklendirir. Ama pod'lara yetecek kadar node yoksa ne olur? **Cluster Autoscaler (CA)**, bu sorunu çözer: pod'lar Pending kaldığında node ekler, boş kalan node'ları ise siler.

---

## Mimari

```
[Yeni pod] → Pending (kaynak yok)
     ↓
[Cluster Autoscaler]
     ↓ Node Group'u incele
     ↓ Yeni node eklenebilir mi?
     ↓ Evet → Cloud API çağır → Node oluştur → Pod schedule edilir

[Boş Node] → Kullanım < %50, 10 dakika boyunca
     ↓
[Cluster Autoscaler]
     ↓ Pod'ları başka node'a taşıyabilir mi?
     ↓ Evet → Node'u drain et → Cloud API → Node'u sil
```

---

## Kurulum

### AWS EKS

```bash
# EKS Node Group'una gerekli tag'ler eklenmeli
# k8s.io/cluster-autoscaler/enabled: "true"
# k8s.io/cluster-autoscaler/<cluster-name>: "owned"

helm repo add autoscaler https://kubernetes.github.io/autoscaler

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-cluster \
  --set awsRegion=eu-west-1 \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789:role/cluster-autoscaler
```

### Azure AKS

```bash
# AKS'ta CA built-in olarak gelir
az aks update \
  --resource-group my-rg \
  --name my-cluster \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10
```

### GKE

```bash
gcloud container clusters update my-cluster \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=10 \
  --zone=europe-west1-b
```

### Bare-Metal / On-Prem (Karpenter)

```bash
# CA yerine Karpenter (daha modern, AWS-native)
helm repo add karpenter https://charts.karpenter.sh
helm install karpenter karpenter/karpenter \
  --namespace karpenter \
  --create-namespace \
  --set clusterName=my-cluster \
  --set aws.defaultInstanceProfile=KarpenterNodeInstanceProfile
```

---

## Cluster Autoscaler Yapılandırması

```yaml
# Deployment üzerindeki önemli flag'ler
command:
  - ./cluster-autoscaler
  - --cloud-provider=aws
  - --nodes=2:20:eks-node-group-xxx   # min:max:node-group-adı
  - --scale-down-enabled=true
  - --scale-down-delay-after-add=10m   # Node eklendikten sonra scale-down bekleme
  - --scale-down-unneeded-time=10m     # Node ne kadar süre boş kalırsa silinsin
  - --scale-down-utilization-threshold=0.5   # %50 altı → boş sayılır
  - --max-node-provision-time=15m      # Node hazır olma timeout
  - --skip-nodes-with-local-storage=false
  - --skip-nodes-with-system-pods=true  # kube-system pod'u olan node'u silme
  - --balance-similar-node-groups=true  # Benzer node group'ları dengele
  - --expander=least-waste             # Hangi node group'u genişletecek? (least-waste | random | price | priority)
  - --v=4
```

---

## Expander Stratejileri

| Strateji | Davranış | Kullanım |
|:---------|:---------|:---------|
| `least-waste` | En az kaynak israf eden group | **Varsayılan önerim** |
| `random` | Rastgele seç | Test |
| `price` | En ucuz node group | Maliyet optimizasyonu |
| `priority` | Priority class'a göre | Özel ihtiyaçlar |

---

## Pod Annotations (CA Kontrolü)

```yaml
# Bu pod'u asla taşıma (scale-down'da node korunur)
metadata:
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "false"

# Spot node'larda çalışan kritik olmayan pod'lar için
metadata:
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "true"
```

---

## PodDisruptionBudget ile Entegrasyon

```yaml
# CA scale-down yaparken PDB'ye uyar
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: production
spec:
  minAvailable: 2       # Scale-down sırasında en az 2 pod ayakta
  selector:
    matchLabels:
      app: api
# Eğer PDB ihlal edilecekse CA o node'u silmez
```

---

## Karpenter (Modern Alternatif)

CA'dan farklı olarak Karpenter, node group kavramını ortadan kaldırır ve pod gereksinimlerine göre en uygun node tipini seçer.

```yaml
# NodePool — hangi node tiplerini kullanabilir?
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
      - key: karpenter.io/instance-category
        operator: In
        values: ["c", "m", "r"]
      - key: karpenter.io/instance-cpu
        operator: In
        values: ["4", "8", "16", "32"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default

  disruption:
    consolidationPolicy: WhenUnderutilized   # Boş node'ları birleştir
    consolidateAfter: 30s
    expireAfter: 720h    # 30 gün sonra node'u yenile (güvenlik)

  limits:
    cpu: 1000
    memory: 4000Gi
```

```yaml
# EC2NodeClass — hangi AMI ve subnet?
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023
  role: KarpenterNodeRole
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeSize: 100Gi
      volumeType: gp3
      encrypted: true
```

---

## İzleme

```bash
# CA logları
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50

# Pending pod'lar (CA'nın tetikleyicisi)
kubectl get pods -A --field-selector=status.phase=Pending

# Node durumu
kubectl get nodes -o wide
kubectl describe node <node> | grep -A5 "Conditions\|Allocatable"
```

```promql
# Prometheus: Pending pod sayısı (CA tetiklenecek mi?)
count(kube_pod_status_phase{phase="Pending"}) > 0

# Node sayısı zamanla
count(kube_node_info) by (node)

# Node kullanım oranı (scale-down kararı için)
sum(kube_pod_container_resource_requests{resource="cpu"}) by (node) /
sum(kube_node_status_allocatable{resource="cpu"}) by (node)
```

---

## CA vs Karpenter Karşılaştırması

| Özellik | Cluster Autoscaler | Karpenter |
|:--------|:-------------------|:----------|
| Node Group | Zorunlu | Gerekmez |
| Node tipi seçimi | Sınırlı | **Dinamik** |
| Hız | ~3-5 dakika | **~30-60 saniye** |
| Cloud desteği | Tüm cloud | AWS, Azure (beta) |
| Spot entegrasyonu | Manuel | **Yerleşik** |
| Karmaşıklık | Orta | Orta |
| Olgunluk | Yüksek | Hızla olgunlaşıyor |

> [!TIP]
> AWS kullanıyorsanız **Karpenter**'ı tercih edin — çok daha hızlı, akıllı ve esnektir. Diğer cloud'larda Cluster Autoscaler kullanın.
