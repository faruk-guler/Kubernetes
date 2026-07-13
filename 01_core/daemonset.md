# DaemonSet Nedir ve Nasıl Kullanılır?

Kubernetes'te podlar genellikle belirli bir sayıda replika ile çalıştırılan Deployment nesneleri üzerinden yönetilir. Ancak bazı durumlarda, bir pod'un kümedeki **istisnasız her düğümde (worker node) tam olarak bir kopya** halinde çalışmasını isteriz. Bu özel iş yükü (workload) türüne **DaemonSet (ds)** denir.

---

## 1. DaemonSet Çalışma Prensibi

DaemonSet, tanımlanan pod şablonunu kümede bulunan her düğüme dağıtır.
* **Yeni Düğüm Ekleme:** Kümeye yeni bir worker node eklendiğinde, DaemonSet bunu fark eder ve o düğüm üzerinde de otomatik olarak yeni bir pod başlatır.
* **Düğüm Silme:** Bir düğüm kümeden çıkarıldığında, o düğümdeki DaemonSet pod'u da silinir ve Kubernetes bu pod'u başka bir düğüme taşımaya çalışmaz (çünkü her düğümde zaten 1 kopya vardır).
* **Seçici Dağıtım (NodeSelector):** Eğer tüm düğümlerde değil de sadece belirli düğümlerde (örneğin sadece GPU'lu düğümlerde) çalışmasını istiyorsanız, DaemonSet içinde `nodeSelector` veya `affinity` tanımlayabilirsiniz.

---

## 2. Yaygın Kullanım Senaryoları

DaemonSet'ler genellikle altyapısal servisler ve "arka plan ajanları" (system agents) için kullanılır:

1. **Log Toplayıcılar (Logging Agents):** Her düğümün kendi lokal log dosyalarını toplayıp merkezi bir log sistemine (Elasticsearch, Loki vb.) göndermek için (Örn: FluentBit, Filebeat, Logstash).
2. **Metrik Toplayıcılar (Monitoring Agents):** Her düğümün CPU, RAM ve disk tüketimini ölçüp Prometheus'a göndermek için (Örn: Prometheus Node Exporter).
3. **Ağ Çözümleri (CNI):** Kümedeki pod'ların birbirleriyle haberleşmesini sağlayan ağ eklentileri (CNI) her düğümde çalışmak zorundadır (Örn: Cilium, Calico, Flannel).
4. **Güvenlik ve Tehdit Algılama:** Düğümler üzerindeki sistem çağrılarını canlı izlemek ve şüpheli aktiviteleri engellemek için (Örn: Falco, Tetragon).

---

## 3. Örnek DaemonSet Yapılandırması

Aşağıda, kümedeki her düğümde çalışıp sistem kaynaklarını izleyen bir `fluent-bit` DaemonSet tanımı bulunmaktadır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [daemonset_manifest.yaml](../Manifests/01_core/daemonset_manifest.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Zamanlama ve Toleranslar (Taints & Tolerations)

DaemonSet'ler, Kubernetes kontrol düzlemindeki `Scheduler` bileşeni tarafından yönetilir.

Normal pod'lar Master (Control-plane) düğümlerine üzerlerindeki Taint'ler (lekeler) nedeniyle gidemezken, DaemonSet pod'larının genellikle tüm sunuculara gitmesi istenir. Bu yüzden DaemonSet pod şablonlarında varsayılan olarak şu toleranslar eklenmelidir:

```yaml
spec:
  template:
    spec:
      tolerations:
      - operator: Exists
        effect: NoSchedule
      - operator: Exists
        effect: NoExecute
```
Bu toleranslar, DaemonSet'in master düğümler de dahil olmak üzere kümedeki her sunucuya kurulmasını sağlar.

---

## 5. Yönetim Komutları

DaemonSet nesnelerini yönetmek için kullanılan temel `kubectl` komutları:

```bash
# Kümedeki DaemonSet'leri listeleme
kubectl get daemonset -n kube-system

# DaemonSet detaylarını inceleme
kubectl describe daemonset fluent-bit -n kube-system

# DaemonSet güncelleme durumunu takip etme
kubectl rollout status daemonset/fluent-bit -n kube-system

# DaemonSet'i önceki versiyonuna geri döndürme (rollback)
kubectl rollout undo daemonset/fluent-bit -n kube-system
```
