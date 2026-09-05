# Taints (Lekeler) ve Tolerations (Toleranslar)

Kubernetes'te Affinity kuralları, pod'ların belirli düğümlere (nodes) yerleşmek istemesiyle (yani "çekim" gücüyle) ilgilidir.

**Taint** (Leke/Lekeleme) ise bunun tam tersidir: **Düğümün pod'ları kendinden uzaklaştırmasıdır ("itme" gücü).** **Toleration** (Tolerans/Panzehir) ise pod'ların bu itme gücünü etkisiz kılıp o düğüme yerleşmesini sağlayan mekanizmadır.

---

## 1. Taints ve Tolerations Nasıl Çalışır?

Bir düğüme leke (taint) sürdüğünüzde, pod'lara bu lekeye karşı bir panzehir (toleration) tanımlamadığınız sürece, o düğüme hiçbir pod yerleşemez.

### Düğümü Taint Etmek

```bash
# gpu-node-1 düğümünü "ekip=yapay-zeka" şeklinde taint ederiz
kubectl taint nodes gpu-node-1 ekip=yapay-zeka:NoSchedule
```

### Poda Toleration Tanımlamak

Yukarıdaki GPU sunucusuna gitmek isteyen bir pod manifestosuna şu toleransı yazarız:

```yaml
spec:
  tolerations:
  - key: "ekip"
    operator: "Equal"
    value: "yapay-zeka"
    effect: "NoSchedule"
```

---

## 2. Taint Etkileri (Taint Effects)

Taint tanımlarken 3 farklı davranış (effect) belirleyebiliriz:

1. **`NoSchedule` (Sert Kural):** Eğer pod lekeye karşı bir toleransa sahip değilse, bu düğüme **kesinlikle planlanamaz (zamanlanamaz)**. Ancak düğüm taint edilmeden önce orada zaten çalışmakta olan toleranssız pod'lar çalışmaya devam eder (onlar silinmez).
2. **`PreferNoSchedule` (Yumuşak Kural):** Kubernetes mümkünse bu düğüme toleranssız pod yerleştirmemeye çalışır. Ancak kümede başka boş yer kalmamışsa, toleranssız pod'lar da çaresizlikten buraya yerleşebilir.
3. **`NoExecute` (Tahliye Kuralı):** En agresif etkidir. Düğüm taint edildiği anda, orada çalışan ve bu lekeye toleransı olmayan tüm mevcut pod'lar **anında öldürülür ve tahliye edilir (evicted)**.

---

## 3. Kordon Altına Alma (Cordon) ve Tahliye (Drain) Süreçleri

Bir sistem yöneticisi düğüm üzerinde işletim sistemi güncellemesi veya fiziksel bakım yapacağı zaman düğümü güvenli şekilde boşaltmak ister. Bu işlemde Taint mekanizması otomatik olarak kullanılır:

### A. Cordon (Düğümü Kilitleme)

```bash
kubectl cordon node-01
```

Bu komut, `node-01` düğümüne otomatik olarak `node.kubernetes.io/unschedulable:NoSchedule` taint'ini sürer. Düğüme yeni pod gelmesi engellenir, ancak içerideki mevcut pod'lar çalışmaya devam eder.

### B. Drain (Düğümü Boşaltma)

```bash
kubectl drain node-01 --ignore-daemonsets --delete-emptydir-data
```

Bu komut ise düğüme `NoExecute` taint'ini uygulayarak düğümde çalışan (DaemonSet'ler hariç) tüm pod'ları güvenli bir şekilde kapatır ve kümedeki diğer uygun düğümlere taşır.

---

## 4. Örnek Yapılandırma Manifesti

Bölüm 1'de uyguladığımız `ekip=yapay-zeka:NoSchedule` taint'ine sahip sunucuda çalışabilmesi için toleransı tanımlanmış yalın bir Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ml-worker
spec:
  # Pod'un lekeye tahammül etmesini sağlayan tolerans
  tolerations:
    - key: "ekip"
      operator: "Equal"
      value: "yapay-zeka"
      effect: "NoSchedule"
  # Pod'un özellikle bu düğümü tercih etmesini sağlayan seçici
  nodeSelector:
    ekip: yapay-zeka
  containers:
    - name: app
      image: alpine
```

---

## Özet

* **Taint Düğüme, Toleration Pod'a:** Taint düğümü savunur, Toleration pod'a o savunmayı aşma anahtarı verir.
* **Toleration Seçici Değildir:** Toleration tek başına pod'u o düğüme çekmez; pod'un diğer standart düğümlere gitmesini engellemek için **NodeSelector** veya **Node Affinity** ile birlikte kullanılmalıdır.
* **Effect Farkı:** `NoSchedule` sadece yeni yerleştirmeleri etkilerken; `NoExecute` düğümdeki mevcut uyumsuz pod'ları da hemen tahliye eder.

