# Kubecost ile Maliyet Yönetimi (FinOps)

## Neden Maliyet Görünürlüğü?

Bulut sağlayıcıların faturaları karmaşıktır. Hangi uygulama, hangi ekip veya hangi mikroservisin ne kadar CPU/RAM tükettiğini ve bunun para karşılığını bilmek artık zorunludur. **FinOps**, mühendislik ekiplerinin maliyet kararlarını sahiplenmesidir.

## Kubecost Kurulumu

```bash
# Helm repo ekle
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/
helm repo update

# Kurulum
helm install kubecost cost-analyzer/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set global.prometheus.enabled=false \
  --set global.prometheus.fqdn=http://prometheus.monitoring:9090

# Kubecost UI
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
# http://localhost:9090
```

## Temel Kavramlar: Request vs. Usage

Maliyetleri düşürmenin en hızlı yolu **Efficiency (Verimlilik)** skoruna bakmaktır:

| Kavram | Açıklama |
|:---|:---|
| **Request Cost** | Pod'un talep ettiği (rezerve edilen) kaynakların maliyeti |
| **Usage Cost** | Pod'un gerçekte kullandığı kaynakların maliyeti |

Eğer `Request >> Usage` ise paranızı boşa harcıyorsunuz. Kubecost size otomatik olarak **Right-sizing** önerileri sunar.

```bash
# Kubecost CLI ile maliyet raporu
kubectl cost namespace --show-all-resources 2h
kubectl cost deployment --show-cpu --show-memory -n production
```

## Maliyet Alerting (FinOps)

```yaml
apiVersion: kubecost.com/v1alpha1
kind: Alert
metadata:
  name: daily-budget-alert
  namespace: kubecost
spec:
  type: budget
  threshold: 100                    # Günlük 100$ sınırı
  window: 1d
  aggregation: namespace
  filter: production
  notifications:
    slack:
      webhook: https://hooks.slack.com/services/...
      channel: "#finops-alerts"
    email:
    - finops-team@company.com
```

## Tasarruf Stratejileri

### 1. Right-sizing

```bash
# Kubecost önerilerini al
kubectl cost savings --show-recommendations -n production
```

### 2. Spot Instance Kullanımı

```yaml
# Kritik olmayan iş yükleri için Spot node tolerasyonu
spec:
  tolerations:
  - key: "cloud.google.com/gke-spot"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  nodeSelector:
    cloud.google.com/gke-spot: "true"
```

### 3. Cluster Autoscaler ile Boş Node Kapatma

```yaml
# Cluster Autoscaler yapılandırması
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - command:
        - ./cluster-autoscaler
        - --cloud-provider=aws
        - --scale-down-delay-after-add=10m
        - --scale-down-unneeded-time=10m     # 10 dk boş kalırsa kapat
        - --skip-nodes-with-local-storage=false
```

### 4. Namespace ResourceQuota

```yaml
# Her ekibe bütçe sınırı
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-budget
  namespace: team-frontend
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
```

> [!TIP]
> Kubecost ile Grafana dashboard entegrasyonu yaparak maliyet verilerini monitoring ekibinizle aynı panelde görebilirsiniz. Grafana Dashboard ID: **15757**.
