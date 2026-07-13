# İleri Pod Teknikleri ve Statik Pod'lar (Advanced Pod Techniques)

Kubernetes'te podlar genellikle kontrol düzlemi (Control Plane - API Server) ve denetleyiciler (Controllers) tarafından yönetilir. Ancak bazı ileri düzey senaryolarda, Kubernetes API Server devrede olmadan doğrudan düğüm (node) seviyesinde çalışan podlara veya özel işlem alanı paylaşım modellerine ihtiyaç duyarız.

Bu bölümde, **Statik Pod'lar (Static Pods)**, süreç paylaşımı ve gelişmiş pod tekniklerini ele alacağız.

---

## 1. Statik Pod'lar (Static Pods) Nedir?

Statik pod'lar, API Server yerine doğrudan ilgili düğüm üzerindeki **kubelet** ajanı tarafından yönetilen ve denetlenen özel pod'lardır.

* **API Server Bağımsızlığı:** Kümeye ait API Server, etcd veya scheduler çalışmasa bile, kubelet kendi lokalindeki statik podları ayakta tutmaya ve çalıştırmaya devam eder.
* **Kullanım Alanı:** Kubernetes kontrol düzlemi bileşenlerinin kendileri (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`) genellikle `kubeadm` kurulumlarında birer statik pod olarak koşturulur.
* **Salt Okunur (Mirror Pod) Yapısı:** kubelet, statik podları API Server'a bildirerek orada salt okunur birer "ayna nesnesi" (mirror pod) oluşturur. `kubectl get pods` ile bu podları görebilirsiniz ancak `kubectl delete` ile silemezsiniz. Silseniz bile kubelet dosyayı okuyup pod'u anında yeniden yaratır.

### Statik Pod Tanımlama Yöntemi

kubelet, statik pod manifestolarını düğüm üzerindeki belirli bir klasörden okur. Bu klasörün yolu kubelet yapılandırma dosyasında (`/var/lib/kubelet/config.yaml`) tanımlanır:

```yaml
staticPodPath: /etc/kubernetes/manifests
```

Bu klasörün altına koyulan her geçerli Pod YAML dosyası, kubelet tarafından otomatik olarak algılanır ve o düğüm üzerinde bir pod olarak başlatılır.

---

## 2. Statik Pod Oluşturma ve Yönetme Adımları

### Adım 1: Düğüme SSH ile Bağlanma ve Dizin Kontrolü

```bash
ssh root@worker-node-01
ls -la /etc/kubernetes/manifests
```

### Adım 2: Statik Pod YAML Dosyasını Oluşturma

`/etc/kubernetes/manifests/static-web.yaml` dosyası oluşturulur:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gelismis_pod_teknikleri_manifest_1.yaml](../Manifests/01_core/gelismis_pod_teknikleri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Adım 3: Çalışma Durumunu Kontrol Etme

Kubelet dosyayı algılayıp pod'u başlattığında, pod adı otomatik olarak düğüm adıyla birleştirilir (`static-web-worker-node-01` gibi):

```bash
# Master node üzerinden sorgulama
kubectl get pods
# NAME                            READY   STATUS    RESTARTS   AGE
# static-web-worker-node-01       1/1     Running   0          45s
```

---

## 3. Süreç Alanı Paylaşımı (Share Process Namespace)

Varsayılan olarak, bir pod içerisindeki konteynerler birbirinin süreçlerini (processes) göremez. Ancak sorun giderme veya ortak işlem yürütme amacıyla pod seviyesinde süreç alanı paylaşımı aktif edilebilir.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gelismis_pod_teknikleri_manifest_2.yaml](../Manifests/01_core/gelismis_pod_teknikleri_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu yapılandırma aktif olduğunda, `debugger` konteynerinin içine girildiğinde `app` konteynerine ait Python süreci doğrudan listelenebilir ve yönetilebilir:

```bash
kubectl exec -it process-sharing-pod -c debugger -- ps aux
# PID   USER     TIME  COMMAND
#   1   root      0:00 /pause (Namespace sahibi pause container)
#   6   root      0:00 python -m http.server 8080
#  12   root      0:00 sh -c sleep 3600
```

---

## 4. Konteyner Türleri Karşılaştırma Matrisi

Kubernetes'te kullanabileceğimiz tüm konteyner türlerinin davranış farkları aşağıda özetlenmiştir:

| Özellik | Init Container | Sidecar (Native) | Uygulama Konteyneri | Ephemeral Container | Statik Pod |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Başlama Zamanı** | En önce, sıralı | Init'lerden sonra | Sidecar'lardan sonra | Sorun giderme anında | Kubelet başlayınca |
| **Bitiş Modeli** | Başarıyla sonlanmalı | Ana uygulama ile biter | Uygulama bitince | Geçici / Manuel | Düğüm kapanınca |
| **CRI Probe Desteği** | ❌ Hayır | ✅ Evet | ✅ Evet | ❌ Hayır | ✅ Evet |
| **Yöneten Bileşen** | API Server / Kubelet | API Server / Kubelet | API Server / Kubelet | API Server / Kubelet | Doğrudan Düğüm Kubelet'i |

---

## Özet

İleri pod teknikleri, Kubernetes'in sınırlarını esnetmemize olanak tanır. **Statik pod'lar**, Kubernetes'in kendi altyapısını ayakta tutan çekirdek mekanizmadır. **Süreç paylaşımı** ve gelişmiş konteyner tipleri ise özellikle loglama, izleme, güvenlik ve sıfır kesintili sorun giderme senaryolarında üretim ortamlarının kararlılığını artırır.
