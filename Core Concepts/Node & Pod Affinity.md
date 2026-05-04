# Node & Pod Affinity

Affinity & Anti-Affinity, pod'ların hangi node'larda çalışacağını belirlemek için `nodeSelector`'dan çok daha esnek ve güçlü bir yöntemdir. Hem node etiketlerine hem de aynı cluster'da çalışan diğer pod'lara göre kural yazılabilir.

## Ne Zaman Kullanılır?

- Pod'ların belirli donanım/lokasyona sahip node'larda çalışmasını zorlamak
- Belirli pod'ların **birlikte** (co-located) veya **ayrı** node'larda çalışmasını sağlamak
- Zorunlu kurallar yerine **tercih** (soft) kuralları tanımlamak
- Cache + API pod çiftlerini daima aynı node'da tutmak

---

## İki Tür Affinity

| Tür | Amaç |
|---|---|
| **Node Affinity** | Pod → Node etiketlerine göre kural |
| **Inter-Pod Affinity/Anti-Affinity** | Pod → Diğer pod etiketlerine göre kural |

---

## Node Affinity

### requiredDuringSchedulingIgnoredDuringExecution

Scheduler, pod'u **mutlaka** bu kuralı karşılayan bir node'a atamalıdır. Kural sağlanmazsa pod `Pending` kalır.

### preferredDuringSchedulingIgnoredDuringExecution

Scheduler, kuralı uygulamaya çalışır; uygun node yoksa başka bir node'a da atayabilir. `weight` (1–100) değeri önceliği belirler.

> [!NOTE]
> Her iki tanımdaki `IgnoredDuringExecution` kısmı, pod bir node'a schedule edildikten sonra node'un label'ları değişse bile pod'un **tahliye edilmeyeceği** anlamına gelir.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-node-affinity
spec:
  affinity:
    nodeAffinity:
      # ZORUNLU: Bu kural sağlanmadan pod schedule edilmez
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - eu-west-1a
            - eu-west-1b
      # TERCİH: Mümkünse SSD diskli node'a git
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: node-type
            operator: In
            values:
            - ssd
  containers:
  - name: app
    image: nginx:1.27
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"
```

### Desteklenen Operatörler

| Operatör | Anlamı |
|---|---|
| `In` | Label değeri listedeki değerlerden biri olmalı |
| `NotIn` | Label değeri listede olmamalı |
| `Exists` | Label key mevcut olmalı (value önemsiz) |
| `DoesNotExist` | Label key mevcut olmamalı |
| `Gt` | Label değeri belirtilen değerden büyük olmalı |
| `Lt` | Label değeri belirtilen değerden küçük olmalı |

> [!TIP]
> Aynı pod için hem `nodeSelector` hem `nodeAffinity` tanımlanırsa, node her iki kuralı da sağlamalıdır.

---

## Inter-Pod Affinity & Anti-Affinity

Node etiketleri yerine, **o node üzerinde çalışan pod'ların etiketlerine** göre kural yazılır.

> [!WARNING]
> Inter-pod affinity/anti-affinity büyük cluster'larda (birkaç yüz node üzeri) scheduling sürecini yavaşlatabilir. Dikkatli kullanın.

### Senaryo: Cache + API Birlikteliği

Her `rest-api` pod'u, bir `cache` pod'u ile **aynı node'da** çalışsın (affinity); ancak aynı node'da **yalnızca bir** `rest-api` olsun (anti-affinity):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rest-api
  labels:
    app: rest-api
spec:
  affinity:
    podAffinity:
      # Cache pod'u olan bir node'a git
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - cache
        topologyKey: kubernetes.io/hostname
    podAntiAffinity:
      # Aynı node'da başka rest-api olmasın
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - rest-api
        topologyKey: kubernetes.io/hostname
  containers:
  - name: rest-api
    image: my-api:v2
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
```

### topologyKey Değerleri

| topologyKey | Kapsam |
|---|---|
| `kubernetes.io/hostname` | Aynı node |
| `topology.kubernetes.io/zone` | Aynı availability zone |
| `topology.kubernetes.io/region` | Aynı region |

---

## Affinity vs nodeSelector vs Taint/Toleration

| Özellik | nodeSelector | Taint/Toleration | Affinity |
|---|---|---|---|
| Esneklik | Düşük | Orta | **Yüksek** |
| Soft kural (tercih) | ❌ | ❌ | ✅ |
| Pod-Pod ilişkisi | ❌ | ❌ | ✅ |
| Anti-affinity | ❌ | ✅ (taint) | ✅ |
| Operator desteği | ❌ | ❌ | ✅ |

---

## Pratik: Zone Dağılımı (Anti-Affinity)

Yüksek erişilebilirlik için pod replika'larını farklı zone'lara dağıtın:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: my-app
        topologyKey: topology.kubernetes.io/zone
```

> [!TIP]
> Kubernetes 1.27+ ile gelen `topologySpreadConstraints`, bu senaryolar için affinity'ye kıyasla daha sade ve önerilen yaklaşımdır.

---

## Pod Priority & Preemption

Düşük öncelikli pod'ları feda ederek kritik pod'lara yer açma mekanizmasıdır.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-prod
value: 1000000
globalDefault: false
description: "Kritik production servisleri"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority-batch
value: 100
globalDefault: false
description: "Batch ve arka plan işler"
```

```yaml
# Pod'a priority ver
spec:
  priorityClassName: high-priority-prod
  containers:
  - name: app
    image: my-critical-app:v1
```

**Preemption:** Yüksek öncelikli pod schedule edilemezse, scheduler düşük öncelikli pod'ları tahliye eder ve yer açar.

> [!WARNING]
> `preemptionPolicy: Never` ile bir PriorityClass'ı preemption olmadan da tanımlayabilirsiniz — yüksek önceliğe sahip ama başkasını tahliye etmeyen pod'lar için.

---

## topologySpreadConstraints (Önerilen — K8s 1.27+)

Affinity'ye kıyasla daha sade, zone bazlı dağılım için modern yaklaşım:

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1                              # Zone'lar arasındaki max fark
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule        # Kural sağlanamazsa Pending
    labelSelector:
      matchLabels:
        app: my-app
```
