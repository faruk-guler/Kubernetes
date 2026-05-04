# Topology Spread Constraints

Topology Spread Constraints, pod'ların node'lar, availability zone'lar ve region'lar arasında dengeli dağılmasını sağlar. Tüm pod'lar aynı zone'a düştüğünde o zone'un düşmesi tüm uygulamayı çökertir — bu kısıtlamalar bunu önler.

---

## Neden Gerekli?

```
Affinity/Anti-affinity: "Bu pod şu node'a gitsin / gitmesin" (binary)
Topology Spread:        "Pod'ları mümkün olduğunca eşit dağıt" (gradual)

Senaryo: 6 replica, 3 zone (eu-west-1a, 1b, 1c)

Spread olmadan (şans eseri):
  zone-a: 4 pod
  zone-b: 2 pod
  zone-c: 0 pod   ← zone-a düşerse 4 pod gider!

Spread ile (maxSkew: 1):
  zone-a: 2 pod
  zone-b: 2 pod
  zone-c: 2 pod   ← Herhangi bir zone düşse 4 pod çalışmaya devam eder ✅
```

---

## Temel Yapı

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1                          # İzin verilen maksimum dengesizlik
    topologyKey: topology.kubernetes.io/zone   # Dağılım kriteri
    whenUnsatisfiable: DoNotSchedule    # Kural ihlalinde ne yap?
    labelSelector:
      matchLabels:
        app: api                         # Hangi pod'ları say?
```

**Temel parametreler:**
```
maxSkew          → En kalabalık ve en az dolu topology arasındaki max fark
topologyKey      → Node label'ı (zone, region, node adı vb.)
whenUnsatisfiable:
  DoNotSchedule  → Kural sağlanamazsa pod'u pending bırak (sıkı)
  ScheduleAnyway → Kural sağlanamazsa yine de dağıt (esnek)
labelSelector    → Hangi pod'ları sayarak dengeyi hesapla
```

---

## Zone Dağılımı

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
spec:
  replicas: 6
  template:
    metadata:
      labels:
        app: api
    spec:
      topologySpreadConstraints:
      # Zone bazlı dağılım
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: api

      # Aynı zamanda node bazlı dağılım (zone içinde de dengeli)
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway   # Node bazlı esnek
        labelSelector:
          matchLabels:
            app: api

      containers:
      - name: api
        image: company/api:v1.2.0
```

---

## Kritik Servis — Çok Katmanlı Dağılım

```yaml
spec:
  replicas: 9     # 3 zone × 3 node = 9
  template:
    metadata:
      labels:
        app: payment-service
        tier: critical
    spec:
      topologySpreadConstraints:
      # 1. Region'lar arası dağılım (DR için)
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/region
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: payment-service

      # 2. Zone'lar arası dağılım
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: payment-service

      # 3. Node'lar arası dağılım (zone içinde)
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: payment-service
```

---

## matchLabelKeys (K8s 1.27+)

Farklı Deployment revision'larının birbirini etkilemesini engeller:

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: api
  matchLabelKeys:
  - pod-template-hash    # Sadece aynı revision'ı say
```

```
matchLabelKeys olmadan:
  v1 pod'lar + v2 pod'lar birlikte sayılır → rolling update sırasında dengesizlik

matchLabelKeys ile:
  Her revision kendi içinde dengeli dağılır ✅
```

---

## minDomains (K8s 1.25+ GA)

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  minDomains: 3     # En az 3 zone olmalı, yoksa pod'u pending bırak
  labelSelector:
    matchLabels:
      app: api
```

---

## Node Affinity ile Birlikte Kullanım

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-type
            operator: In
            values: [compute]   # Sadece compute node'lara git

  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: api
    # nodeAffinityPolicy: Honor → Sadece affinity'e uyan node'ları say
    nodeAffinityPolicy: Honor
```

---

## Pod Dağılımını Doğrulama

```bash
# Pod'ların zone dağılımını gör
kubectl get pods -n production -l app=api \
  -o custom-columns=\
"NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\.kubernetes\.io/zone"

# Node label'larını görüntüle
kubectl get nodes -L topology.kubernetes.io/zone,topology.kubernetes.io/region

# Spread constraint ihlali — Pending pod'u incele
kubectl describe pod <pending-pod> -n production
# Events:
#   Warning  FailedScheduling  0/6 nodes are available:
#   3 node(s) didn't match pod topology spread constraints.
```

---

## Cluster-Wide Varsayılan (Scheduler Config)

```yaml
# Tüm pod'lara otomatik spread uygulamak için scheduler konfigürasyonu
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  pluginConfig:
  - name: PodTopologySpread
    args:
      defaultConstraints:
      - maxSkew: 3
        topologyKey: "topology.kubernetes.io/zone"
        whenUnsatisfiable: ScheduleAnyway
      defaultingType: List
```

---

## Topology Spread vs Pod Anti-Affinity

| | Topology Spread | Pod Anti-Affinity |
|:--|:--|:--|
| **Çalışma** | Dağılımı dengele (gradual) | Aynı yere koyma (binary) |
| **Esneklik** | `ScheduleAnyway` ile esnek | `preferredDuring` ile esnek |
| **Karmaşıklık** | Daha az YAML | Daha fazla YAML |
| **Öneri** | 2026 standardı | Legacy, Spread tercih et |

> [!TIP]
> Cloud provider cluster'larında node'lar `topology.kubernetes.io/zone` label'ıyla gelir. Bare-metal'de bu label'ları node'lara elle eklemeniz gerekir: `kubectl label node node-1 topology.kubernetes.io/zone=rack-a`

> [!IMPORTANT]
> `whenUnsatisfiable: DoNotSchedule` ile `maxSkew: 1` kombinasyonu, zone sayısından fazla replica yoksa pod'ları **pending** bırakabilir. 3 zone için en az 3 replica olmalı — aksi hâlde scheduler kural sağlayamaz.
