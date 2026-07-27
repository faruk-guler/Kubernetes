# DNS ve CoreDNS Derinlemesine İnceleme

Kubernetes'te servis keşfi (service discovery) tamamen DNS (Domain Name System) altyapısı üzerine kuruludur. Kubernetes 1.13 sürümünden itibaren, küme içi DNS hizmeti için de-facto standart olarak **CoreDNS** kullanılmaktadır.

---

## 1. CoreDNS Nasıl Çalışır?

Kubernetes kümesinde başlatılan her podun `/etc/resolv.conf` dosyası kubelet tarafından otomatik olarak aşağıdaki gibi yapılandırılır:

```
nameserver 10.96.0.10      # CoreDNS ClusterIP adresi
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

Bir pod, küme içi veya küme dışı bir adrese gitmek istediğinde sorgu şu akışla çözülür:

```
[ Geliştirici Podu ] ──(nslookup google.com)──► [ CoreDNS Pod (kube-system) ]
                                                     │
                                                     ├──► Küme İçi: API Server'dan çöz
                                                     └──► Küme Dışı: Düğümün resolv.conf'una (Upstream) yönlendir
```

---

## 2. DNS Kayıt Standartları

Kubernetes'te oluşturulan kaynaklar için belirli DNS isimlendirme kuralları (naming conventions) geçerlidir:

### A. Service DNS Kayıtları

* **Standart Servis (ClusterIP):**

    `<servis-adi>.<namespace>.svc.cluster.local` ──► Service ClusterIP'sine çözülür.

* **Headless Servis (`clusterIP: None`):**

    `<servis-adi>.<namespace>.svc.cluster.local` ──► Servis arkasındaki tüm canlı podların IP adreslerini (A kayıtları) döner.

* **Headless Servis Altındaki Podlar (StatefulSet için kritik):**

    `<pod-adi>.<servis-adi>.<namespace>.svc.cluster.local` ──► Doğrudan o spesifik podun IP adresini döner.

### B. Pod DNS Kayıtları

Eğer özel bir yapılandırma yoksa, her podun IP adresinin tireli haliyle bir DNS kaydı oluşur:
`<pod-ip-tire-ile>.<namespace>.pod.cluster.local` (Örn: `10-244-1-15.default.pod.cluster.local`).

---

## 3. CoreDNS Yapılandırması (Corefile)

CoreDNS'in davranışı, `kube-system` ad alanındaki `coredns` ConfigMap'i içerisinde yer alan **Corefile** dosyası ile yönetilir:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [dns_ve_coredns_manifest_1.yaml](../Manifests/05_networking/dns_ve_coredns_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Kritik Corefile Eklentileri (Plugins)

* **kubernetes:** Kubernetes API Server'ı dinleyerek Service ve Pod kayıtlarını oluşturur.
* **forward:** Küme dışı sorguları host makinenin DNS ayarlarına (`/etc/resolv.conf`) yönlendirir.
* **cache:** DNS yanıtlarını bellek üzerinde önbelleğe alarak API Server yükünü azaltır.

---

## 4. `ndots` Mekanizması ve Performans Etkisi

Podların `/etc/resolv.conf` dosyasındaki `ndots:5` parametresi, bir DNS sorgusunun ne zaman "tam nitelikli" (FQDN) sayılacağını belirler. Nokta sayısı 5'ten az olan aramalar için önce arama yolları (search paths) sırayla taranır:

```
# "my-service" aranırken (nokta sayısı 0):
1. my-service.default.svc.cluster.local ──► Bulunamazsa
2. my-service.svc.cluster.local ──► Bulunamazsa
3. my-service.cluster.local ──► Bulunamazsa
4. my-service. (Düğümün kendi DNS sunucusuna sorulur)
```

> [!TIP]
> **Performans İpucu:** Dış dünyaya (Örn: `api.github.com` - 2 nokta) yapılan her sorgu, `ndots:5` nedeniyle önce küme içine sorulur ve gereksiz DNS trafiğine yol açar. Dış ağ sorgularında gecikmeyi azaltmak için adreslerin sonuna nokta koyarak FQDN araması yapın: `api.github.com.`.

---

## 5. NodeLocal DNSCache ile Performans Optimizasyonu

Büyük ölçekli kümelerde CoreDNS üzerindeki yükü ve conntrack tablo baskısını azaltmak için her düğümde yerel DNS önbelleği çalıştıran **NodeLocal DNSCache** kurulmalıdır:

```
[ Pod ] ──► [ 169.254.20.10 (Local DNS Cache) ] ──► (Cache Miss) ──► [ CoreDNS Pod ]
```

### Kurulum Adımı

```bash
# NodeLocal DNS DaemonSet ve servis tanımlarını uygulayın
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
```

---

## 6. DNS Hata Ayıklama (Troubleshooting)

DNS çözümleme sorunlarını teşhis etmek için geçici bir test podu başlatıp sorguları denetleyebilirsiniz:

```bash
# 1. DNS test podunu ayağa kaldırın
kubectl run dns-test --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --restart=Never -it --rm -- bash

# 2. Pod içinde nslookup ve dig komutlarını çalıştırın
nslookup kubernetes.default
dig @10.96.0.10 my-service.default.svc.cluster.local
```
