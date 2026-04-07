# Scheduling: Affinity, Taint/Toleration ve Priority

Bu bölümde pod'ların hangi node'lara yerleştirileceğini kontrol eden mekanizmalar anlatılmaktadır.

---

## 5.1 Node Selector (Basit Yaklaşım)

```bash
# Node'a label ekle
kubectl label node worker-01 disktype=ssd

# Pod içinde kullan
spec:
  nodeSelector:
    disktype: ssd
```

---

## 5.2 Node Affinity

Node Selector'ın daha güçlü ve esnek halidir. Mantıksal operatörler (In, NotIn, Exists, vb.) kullanmanıza olanak tanır.

### Affinity Tipleri
- **requiredDuringSchedulingIgnoredDuringExecution (Hard):** Şart sağlanmazsa pod Pending kalır.
- **preferredDuringSchedulingIgnoredDuringExecution (Soft):** Tercih edilir; sağlanamazsa en uygun node seçilir.

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disktype
            operator: In
            values: ["ssd", "nvme"]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 10
        preference:
          matchExpressions:
          - key: environment
            operator: In
            values: ["prod"]
```

---

## 5.3 Pod Affinity ve Anti-Affinity

Pod'ların birbirleriyle olan ilişkisine göre yerleştirme yapar.

- **Affinity:** "Frontend ile aynı node'da (vaya zone'da) çalış."
- **Anti-Affinity:** "Aynı uygulamanın başka kopyasıyla aynı node'da çalışma (HA için)."

### 💡 Senaryo: Cache ve Frontend Birlikteliği
```yaml
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: frontend
        topologyKey: kubernetes.io/hostname
```

> [!CAUTION]
> **Black Belt Tip: Performance Impact**
> Inter-pod affinity ve anti-affinity kuralları, büyük cluster'larda (500+ node) scheduling sürecini ciddi oranda yavaşlatabilir. Her node'un her pod için kontrol edilmesi gerektiği için maliyetli bir hesaplamadır. Çok büyük ortamlarda `nodeAffinity` tercih edilmelidir.

---

## 5.4 Taint ve Toleration

Node'un "beni sadece belirli pod'lar kullanabilir" demesini sağlar.

- **Taint:** Node üzerindeki kısıt (Örn: `gpu=true:NoSchedule`)
- **Toleration:** Pod üzerindeki izin (Örn: "Ben gpu=true'yu tolere ederim")

```bash
# Node'a taint ekle
kubectl taint node worker-gpu nvidia.com/gpu=true:NoSchedule
```

---

## 5.5 Pod Priority ve Preemption

Düşük öncelikli pod'ları feda ederek kritik pod'lara yer açma mekanizmasıdır.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-prod
value: 1000000
globalDefault: false
description: "Kritik production servisleri"
```

---
*← [Pod İleri](04b_ileri_pod_teknikleri.md) | [Ana Sayfa](../README.md)*
