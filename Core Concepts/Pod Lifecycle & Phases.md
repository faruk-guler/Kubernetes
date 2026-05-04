# Pod Lifecycle & Phases (Pod Yaşam Döngüsü)

Kubernetes'te bir pod, oluşturulduğu andan silinene kadar belirli bir yaşam döngüsü izler. Bu döngüyü anlamak; `Pending`, `CrashLoopBackOff`, `OOMKilled` gibi sorunları doğru teşhis etmenin temelidir.

---

## Pod Phase (Aşamaları)

Pod'un `status.phase` alanı, pod'un yaşam döngüsündeki mevcut konumunu özetler:

| Phase | Açıklama |
|---|---|
| **Pending** | Pod cluster tarafından kabul edildi; ancak bir veya daha fazla container henüz hazır değil. Image indirme veya node bekleme bu aşamada gerçekleşir. |
| **Running** | Pod bir node'a bağlandı, tüm container'lar oluşturuldu. En az biri çalışıyor, başlatılıyor veya restart ediliyor. |
| **Succeeded** | Tüm container'lar başarıyla tamamlandı (`exit code 0`) ve yeniden başlatılmayacak. Job/CronJob için beklenen son durum. |
| **Failed** | Tüm container'lar sonlandı; en az biri başarısız çıktı (`exit code != 0`) veya sistem tarafından kill edildi. |
| **Unknown** | Pod'un durumu alınamıyor — genellikle node ile iletişim kopukluğundan kaynaklanır. |

```bash
# Pod phase'ini görüntüle
kubectl get pod <pod-adı> -o jsonpath='{.status.phase}'

# Tüm pod'ların phase özeti
kubectl get pods -A --field-selector=status.phase=Pending
kubectl get pods -A --field-selector=status.phase!=Running
```

---

## Pod Lifecycle Akışı

```
[API Server'a Kabul]
        ↓
   ┌─ Pending ─────────────────────────────┐
   │  • Scheduler node seçiyor             │
   │  • Container image indiriliyor        │
   │  • Init container'lar çalışıyor       │
   └────────────────────────────────────────┘
        ↓ (Başarılı)
   ┌─ Running ──────────────────────────────┐
   │  • Ana container'lar çalışıyor        │
   │  • Liveness/Readiness probe aktif     │
   │  • Restart politikası geçerli         │
   └────────────────────────────────────────┘
        ↓
   ┌─ Succeeded ──┐   ┌─ Failed ───────────┐
   │ Job tamamlandı│   │ Container crash    │
   │ exit code: 0  │   │ exit code: != 0   │
   └──────────────┘   └────────────────────┘
```

---

## Pod Conditions

Phase'in yanı sıra pod'un `status.conditions` alanı daha detaylı durum bilgisi verir:

| Condition | Açıklama |
|---|---|
| `PodScheduled` | Pod bir node'a atandı |
| `PodReadyToStartContainers` | Sandbox oluşturuldu, ağ yapılandırıldı |
| `Initialized` | Tüm init container'lar başarıyla tamamlandı |
| `ContainersReady` | Tüm container'lar ready durumunda |
| `Ready` | Pod trafik alabilir (Service endpoint'e eklendi) |

```bash
# Koşulları detaylı görüntüle
kubectl describe pod <pod-adı> | grep -A 20 Conditions

# JSON formatında
kubectl get pod <pod-adı> -o jsonpath='{.status.conditions[*].type}'
```

---

## Container States (Container Durumları)

Her container kendi durumunu `status.containerStatuses` altında raporlar:

### Waiting
Container henüz çalışmıyor. `reason` alanı nedeni belirtir:

| Reason | Anlamı |
|---|---|
| `ContainerCreating` | Image indiriliyor veya volume bağlanıyor |
| `ImagePullBackOff` | Image çekilemiyor (registry, credential hatası) |
| `CrashLoopBackOff` | Container sürekli crash oluyor, exponential backoff |
| `ErrImageNeverPull` | `imagePullPolicy: Never` ama image yok |

### Running
Container başarıyla başladı ve çalışıyor.

### Terminated
Container tamamlandı veya başarısız oldu.

```bash
# Container durumunu oku
kubectl get pod <pod-adı> -o jsonpath='{.status.containerStatuses[0].state}'

# CrashLoopBackOff debug
kubectl logs <pod-adı> --previous          # Önceki crash logu
kubectl describe pod <pod-adı>             # Events ve restart sayısı
```

---

## Restart Policy

`spec.restartPolicy` alanı, container başarısız olduğunda ne yapılacağını belirler:

| Politika | Davranış |
|---|---|
| `Always` (varsayılan) | Container her durumda yeniden başlatılır |
| `OnFailure` | Yalnızca başarısız (`exit != 0`) olduğunda yeniden başlatılır |
| `Never` | Asla yeniden başlatılmaz |

```yaml
spec:
  restartPolicy: OnFailure   # Job'lar için önerilen
```

---

## Termination Grace Period

Pod silinirken container'lara `SIGTERM` gönderilir. Varsayılan 30 saniye içinde kapanmazsa `SIGKILL` uygulanır:

```yaml
spec:
  terminationGracePeriodSeconds: 60   # Daha uzun graceful shutdown
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 5"]  # Bağlantıları bitir
```

```bash
# Zorla hemen sil (grace period'u atla)
kubectl delete pod <pod-adı> --grace-period=0 --force
```

---

## Node Failure Durumu

Bir node çökerse veya cluster'dan düşerse:

1. Kubernetes, node'u `NotReady` olarak işaretler (varsayılan: 40 saniye sonra)
2. `node.kubernetes.io/not-ready` ve `node.kubernetes.io/unreachable` taint'leri eklenir
3. `pod-eviction-timeout` (varsayılan: 5 dakika) dolduktan sonra pod'lar `Failed` phase'e alınır
4. ReplicaSet controller, kaybolan pod'ların yerine sağlıklı node'larda yenilerini oluşturur

```bash
# Node durumunu izle
kubectl get nodes -w

# Node üzerindeki pod'ları listele
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-adı>
```

---

## Terminating Durumu

`kubectl delete pod` sonrasında `Terminating` görünür. Bu bir **phase değil**, geçici bir durumdur:

```bash
# Terminating durumunda takılan pod'u zorla sil
kubectl delete pod <pod-adı> --grace-period=0 --force

# Finalizer'lardan kalan pod'u temizle
kubectl patch pod <pod-adı> -p '{"metadata":{"finalizers":null}}'
```

---
