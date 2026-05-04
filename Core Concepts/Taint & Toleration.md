# Taint & Toleration

Taint ve Toleration, belirli node'ların yalnızca uygun pod'ları kabul etmesini sağlayan bir Kubernetes mekanizmasıdır. Node'lara **taint** (leke) eklersiniz; pod'lar ise bu taint'leri tolere ettiklerini **toleration** tanımıyla belirtirler.

## Ne Zaman Kullanılır?

- Belirli node'ları sadece belirli ekiplerin veya uygulamaların kullanımına sunmak
- GPU, SSD gibi özel donanımlı node'lara yalnızca uygun workload'ları yönlendirmek
- Bakım/mavi-yeşil senaryolarında mevcut pod'ları başka node'lara taşımak
- Node sağlık koşulları kötüleştiğinde Kubernetes'in pod'ları otomatik tahliye etmesi

---

## Taint Ekleme (Node Tarafı)

Taint, `key=value:Effect` formatında node'a eklenir:

```bash
# NoSchedule — Toleration olmayan pod'lar bu node'a schedule edilmez
kubectl taint nodes node-1 key1=value1:NoSchedule

# PreferNoSchedule — Mümkünse schedule etme, zorunluysa eder
kubectl taint nodes node-1 key1=value1:PreferNoSchedule

# NoExecute — Schedule etmez + mevcut pod'ları tahliye eder
kubectl taint nodes node-1 key1=value1:NoExecute

# Taint kaldırma (sonuna - eklenir)
kubectl taint nodes node-1 key1=value1:NoSchedule-
```

---

## Toleration Tanımlama (Pod Tarafı)

Toleration, pod spec'ine `tolerations` alanıyla eklenir:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tolerant-pod
spec:
  tolerations:
  - key: "key1"
    operator: "Equal"
    value: "value1"
    effect: "NoSchedule"
  containers:
  - name: nginx
    image: nginx:1.27
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "250m"
        memory: "256Mi"
```

### Operator Değerleri

| Operator | Anlamı |
|---|---|
| `Equal` | key, value ve effect değerleri eşit olmalı (varsayılan) |
| `Exists` | Yalnızca key ve effect eşleşmeli; value kontrolü yapılmaz |

> [!TIP]
> `key` ve `effect` boş bırakılarak `Exists` operatörü kullanılırsa, pod **tüm taint'leri** tolere eder.

---

## Taint Efektleri

### NoSchedule

Toleration tanımı olmayan pod'lar o node'a **kesinlikle** schedule edilmez. Mevcut çalışan pod'lar etkilenmez.

### PreferNoSchedule

Scheduler, pod'u başka bir node'a koymayı dener; uygun node yoksa bu node'u da kullanabilir.

### NoExecute

En güçlü efekt:
1. Toleration'ı olmayan pod'lar schedule **edilmez**.
2. Node'a sonradan eklenen taint, tolerationsız mevcut pod'ları **tahliye eder**.

`tolerationSeconds` ile tahliye için bekleme süresi ayarlanabilir:

```yaml
tolerations:
- key: "node.kubernetes.io/not-ready"
  operator: "Exists"
  effect: "NoExecute"
  tolerationSeconds: 300  # 300 saniye sonra tahliye et
```

---

## Kubernetes Built-in Taint'ler

Kubernetes, node koşulları kötüleştiğinde node'lara otomatik taint ekler (`TaintNodesByCondition` özelliği):

| Node Condition | Otomatik Eklenen Taint |
|---|---|
| `NotReady` | `node.kubernetes.io/not-ready:NoExecute` |
| `Unreachable` | `node.kubernetes.io/unreachable:NoExecute` |
| `OutOfDisk` | `node.kubernetes.io/out-of-disk:NoSchedule` |
| `DiskPressure` | `node.kubernetes.io/disk-pressure:NoSchedule` |
| `MemoryPressure` | `node.kubernetes.io/memory-pressure:NoSchedule` |
| `PIDPressure` | `node.kubernetes.io/pid-pressure:NoSchedule` |
| `NetworkUnavailable` | `node.kubernetes.io/network-unavailable:NoSchedule` |

Node condition'larını görmek için:

```bash
kubectl describe node <node-adı> | grep -A5 Taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

---

## Static Pod vs DaemonSet vs Taint

| | Taint/Toleration | DaemonSet |
|---|---|---|
| Amaç | Belirli pod'ları node'lardan **uzak tut** | Her node'da **bir pod** çalıştır |
| Kontrol | Pod + Node kombinasyonu | API Server → DaemonSet Controller |
| Scheduler | Çalışır | Ignore edilir |

---

## Pratik Senaryo: Dedicated GPU Node

```bash
# Node'u GPU workload'larına ayır
kubectl taint nodes gpu-node-1 dedicated=gpu:NoSchedule

# Sadece GPU pod'ları bu node'a schedule edilsin
```

```yaml
# GPU deployment toleration örneği
tolerations:
- key: "dedicated"
  operator: "Equal"
  value: "gpu"
  effect: "NoSchedule"
```

> [!NOTE]
> Taint & Toleration yalnızca bir **engel** mekanizmasıdır. Pod'u mutlaka o node'a **çekmek** için Node Affinity veya `nodeSelector` ile birlikte kullanın.

---
