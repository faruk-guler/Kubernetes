# Taints (Lekeler) ve Tolerations (Toleranslar)

Kubernetes'te Affinity kuralları, pod'ların belirli düğümlere (nodes) yerleşmek istemesiyle (yani "çekim" gücüyle) ilgilidir. 

**Taint** (Leke/Lekeleme) ise bunun tam tersidir: **Düğümün pod'ları kendinden uzaklaştırmasıdır ("itme" gücü).** **Toleration** (Tolerans/Panzehir) ise pod'ların bu itme gücünü etkisiz kılıp o düğüme yerleşmesini sağlayan mekanizmadır.

---

## 1. Taints ve Tolerations Nasıl Çalışır?

Bir düğüme leke (taint) sürdüğünüzde, pod'lara bu lekeye karşı bir panzehir (toleration) tanımlamadığınız sürece, o düğüme hiçbir pod yerleşemez.

### Düğümü Taint Etmek:
```bash
# gpu-node-1 düğümünü "ekip=yapay-zeka" şeklinde taint ederiz
kubectl taint nodes gpu-node-1 ekip=yapay-zeka:NoSchedule
```

### Poda Toleration Tanımlamak:
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

Aşağıda, sadece GPU düğümlerinde çalışmak üzere tasarlanmış ve buna uygun tolerans tanımlanmış bir test pod manifesti linklenmiştir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [taint_ve_toleration_manifest_1.yaml](../Manifests/01_core/taint_ve_toleration_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
