# Node Selector, Node Affinity ve Pod Affinity

Kubernetes'te bir pod oluşturulduğunda, `Scheduler` (Zamanlayıcı) bu pod'u yerleştirmek için en uygun düğümü (node) seçer. Varsayılan olarak bu seçim düğümlerin CPU ve bellek doluluk oranlarına göre yapılır. 

Ancak bazı durumlarda, pod'ların hangi düğümlerde çalışacağını veya çalışmayacağını özel kurallarla belirlemek isteriz. Bu zamanlama kuralları için **NodeSelector**, **Node Affinity** ve **Pod Affinity / Anti-Affinity** mekanizmaları kullanılır.

---

## 1. NodeSelector: En Basit Zamanlama

`nodeSelector`, bir pod'un belirli etiketlere (labels) sahip düğümlere gitmesini sağlayan en eski ve en basit yöntemdir.

Düğümünüze bir etiket verirsiniz:
```bash
kubectl label nodes node-01 disktype=ssd
```

Ardından pod tanımında bu etiketi seçersiniz:
```yaml
spec:
  nodeSelector:
    disktype: ssd
```

* **Dezavantajı:** Çok katıdır (ya hep ya hiç mantığıyla çalışır). Eğer kümede `disktype=ssd` etiketine sahip boş yer olan bir düğüm yoksa, pod sonsuza dek `Pending` (beklemede) kalır.

---

## 2. Node Affinity (Düğüm Yakınlığı)

Node Affinity, `nodeSelector`'ın daha esnek, mantıksal sorguları (AND, OR, NOT, EXISTS) destekleyen ve "yumuşak/tercih edilen" kurallar koymamıza olanak tanıyan gelişmiş versiyonudur.

İki ana türü vardır:

### A. Sert / Zorunlu Kurallar (Required)
`requiredDuringSchedulingIgnoredDuringExecution`
"Bu kural kesinlikle sağlanmalı, aksi takdirde pod'u çalıştırma."
Örnek: Pod'un sadece GPU'lu düğümlerde (`hardware-type: gpu`) çalışmaya zorlanması.

### B. Yumuşak / Tercih Edilen Kurallar (Preferred)
`preferredDuringSchedulingIgnoredDuringExecution`
"Eğer mümkünse bu düğüme git, ama yer yoksa başka bir düğümde de çalışabilirsin."
* **`weight` (1-100):** Tercih edilen düğümlere ağırlık puanı verilir. Scheduler, kuralları en çok karşılayan ve en yüksek puanı alan düğümü seçer.

---

## 3. Pod Affinity ve Anti-Affinity (Pod'lar Arası Zamanlama)

Düğüm etiketlerine bakmak yerine, **kümede çalışan diğer pod'ların konumlarına göre** karar verme mekanizmasıdır.

### A. Pod Affinity (Birlikte Çalışma)
"Beni, `app=database` etiketine sahip pod'un çalıştığı düğüme yerleştir."
* **Kullanım Amacı:** Ağ gecikmesini (network latency) azaltmak için birbirleriyle yoğun konuşan mikroservisleri (Örn: Web arayüzü ile Redis Cache) aynı düğüm üzerine veya aynı kullanılabilirlik bölgesine (Availability Zone) yerleştirmek.

### B. Pod Anti-Affinity (Ayrı Çalışma)
"Beni, `app=web-server` etiketli pod'ların çalıştığı düğüme **koyma**."
* **Kullanım Amacı:** Yüksek erişilebilirlik (HA) sağlamak. Aynı uygulamanın kopyalarını farklı düğümlere dağıtarak, bir düğüm çöktüğünde tüm servisimizin kapanmasını engelleriz.

---

## 4. `topologyKey` Kavramı

Pod Affinity kurallarında "aynı yer" kavramını tanımlamak için **`topologyKey`** kullanılır.
* Eğer `topologyKey: kubernetes.io/hostname` seçilirse, pod'lar aynı **fiziksel sunucu (düğüm)** düzeyinde birlikte veya ayrı tutulur.
* Eğer `topologyKey: topology.kubernetes.io/zone` seçilirse, pod'lar bulut üzerindeki aynı **kullanılabilirlik bölgesi (zone)** düzeyinde birlikte veya ayrı tutulur.

---

## 5. Örnek Yapılandırma Manifesti

Aşağıdaki bağlantıda, hem Node Affinity (zorunlu ve tercih edilen) hem de Pod Anti-Affinity (yüksek erişilebilirlik için pod'ları ayrı sunuculara dağıtma) kurallarını içeren gelişmiş bir deployment manifesti bulunmaktadır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [node_ve_pod_affinity_manifest_1.yaml](../Manifests/01_core/node_ve_pod_affinity_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
