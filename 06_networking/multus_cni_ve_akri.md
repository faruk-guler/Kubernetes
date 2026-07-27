# Çoklu Ağ Kartı (Multus CNI) ve Edge Cihaz Keşfi (Akri)

Klasik Kubernetes ağ yapısında her podun yalnızca tek bir ağ arayüzü (genellikle `eth0`) olur. Bu arayüz, podun küme içindeki (Cluster IP) trafiği taşımasını sağlar. Ancak telekomünikasyon (5G), edge computing (uç bilişim) ve bazı özel güvenlik senaryolarında podların fiziksel veri merkezi ağlarına doğrudan ve birden fazla kanaldan bağlanması gerekir.

Bu karmaşık ağ ve edge cihaz entegrasyonu problemlerini çözmek için CNCF ekosisteminde **Multus CNI** ve **Akri** projeleri kullanılır.

---

## 1. Multus CNI: Multi-Homed Pods

**Multus CNI**, Kubernetes podlarının **birden fazla ağ arayüzüne (NIC)** sahip olmasını sağlayan bir "meta-CNI" projesidir. Kendisi yeni bir ağ protokolü kurmaz; Calico, Flannel veya Cilium gibi mevcut CNI'ları bir araya getirerek podlara ek kartlar bağlar.

### Neden İhtiyaç Duyulur?

* **Veri ve Kontrol Trafiğinin Ayrılması:** Bir podun kontrol trafiği (Kubernetes API iletişimi) standart pod ağından akarken, yüksek boyutlu veri trafiği (örneğin video yayını veya veri tabanı replikasyonu) doğrudan fiziksel bir 10Gbps karta yönlendirilebilir.
* **Fiziksel Switch Entegrasyonu (SR-IOV / Macvlan):** Sanallaştırma katmanlarını atlayıp podu doğrudan fiziksel ağ anahtarına bağlayarak gecikmeyi (latency) sıfıra indirmek.

### NetworkAttachmentDefinition (NAD)

Multus'ta ikinci ağ kartını tanımlamak için Kubernetes API'sine `NetworkAttachmentDefinition` (NAD) adlı bir Custom Resource uygulanır.

> 📌 **Örnek Yapılandırma:** Macvlan kullanarak podları fiziksel ağa bağlayan NAD örneğine **[multus_manifest_1.yaml](../Manifests/05_networking/multus_manifest_1.yaml)** dosyasından ulaşabilirsiniz.

### Pod Üzerinde Kullanımı

Oluşturulan bu ağ tanımını bir poda bağlamak son derece basittir. Pod manifestinin `annotations` kısmına ağın adını yazmanız yeterlidir:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-nic-pod
  annotations:
    k8s.cni.cncf.io/networks: macvlan-conf # Multus ağını bağla
spec:
  containers:
  - name: app
    image: alpine
    command: ["/bin/sh", "-c", "sleep 3600"]
```

Bu pod ayağa kalktığında, içine girip `ip a` yazdığınızda hem standart K8s IP'sini (`eth0`) hem de fiziksel ağdan doğrudan IP almış olan `net1` arayüzünü görürsünüz.

---

## 2. Akri: Edge Cihazlarını Kubernetes'e Bağlamak

**Akri**, Kubernetes kümesini fiziksel dünyanın sınırlarına (Edge/IoT) genişleten bir CNCF projesidir. Uç noktalarda çalışan Kubernetes kümelerinin (örneğin fabrikadaki bir K3s sunucusunun) etrafındaki IP kameraları, USB sensörleri veya endüstriyel makine arayüzlerini (OPC UA) otomatik olarak keşfetmesini sağlar.

### Çalışma Mantığı

1. **Keşif (Discovery):** Akri ajanları, düğümlerin etrafındaki ağları sürekli tarar (Örn: ONVIF protokolü ile IP kameraları, udev ile USB cihazları arar).
2. **Custom Resource (CRD):** Keşfedilen her cihaz için Kubernetes üzerinde bir `Instance` nesnesi oluşturur.
3. **Broker Pods:** Cihaz keşfedildiği an, Akri o cihaza özel bir "Broker Pod" ayağa kaldırır. Bu pod, cihazla konuşup veriyi Kubernetes ekosisteminin anlayacağı formata (örneğin bir Prometheus metriğine) dönüştürür.
4. **Servis Oluşturma:** Broker podlarının önüne otomatik olarak standart bir Kubernetes Servisi koyar. Yazılımcılar kameranın veya sensörün fiziksel IP'sini bilmeden doğrudan `http://camera-service` üzerinden canlı yayına erişebilirler.

---

## Özet

Multus CNI, Kubernetes'i geleneksel veri merkezi sınırlarından kurtarıp çoklu ağ kartlarıyla donatırken; Akri ise fiziksel cihazları (kamera, sensör vb.) birer Kubernetes servisi haline getirerek BT (Bilgi Teknolojileri) ve OT (Operasyonel Teknolojiler) dünyalarını birleştirir. Özellikle edge ve IoT projelerinde bu iki araç kritik önem taşır.
