# Küme Federasyonu: Liqo ve Submariner ile Çoklu Küme Yönetimi

Çoklu Kubernetes kümesi (Multi-Cluster) yapılarında, her küme kendi içinde bağımsız çalışırken; **Küme Federasyonu (Cluster Federation)** modelinde kümeler birbirinin farkındadır, aralarında güvenli ağ tünelleri kuruludur ve iş yükleri (pods/services) kümeler arasında şeffaf bir şekilde paylaştırılabilir.

---

## 1. Multi-Cluster ve Federasyon Farkı

```
Multi-Cluster:
  [ Cluster A (EU) ]              [ Cluster B (US) ]
  (Bağımsız çalışırlar, sadece GitOps/ArgoCD ortak kodları iki kümeye de basar)

Federasyon (Liqo / Submariner):
  [ Cluster A (EU) ]  ◄──(Ağ Tüneli / Temsili Düğüm)──►  [ Cluster B (US) ]
  (Cluster A, Cluster B'yi sanal bir node olarak görür. A'daki pod doğrudan B'deki pod ile konuşabilir)
```

### Temel Kullanım Senaryoları

* **Buluta Taşma (Burst-to-Cloud):** Kendi veri merkezinizdeki (On-Premise) sunucuların kapasitesi dolduğunda, iş yüklerinin otomatik olarak AWS/GCP üzerindeki yedek kümeye kaydırılması.
* **Felaket Kurtarma (Disaster Recovery):** Ana kümede kesinti yaşandığında, servislerin standby durumundaki ikinci kümede otomatik olarak aktifleşmesi.
* **Veri Yerelliği (Data Locality):** Kullanıcının isteğini, coğrafi olarak en yakın olan kümede karşılamak.

---

## 2. Liqo: Kubernetes-Native Şeffaf Federasyon

**Liqo**, kümeler arasında kaynak paylaşımını kolaylaştırır. Bir küme, diğer kümeyi yerel bir "Sanal Düğüm (Virtual Node)" gibi görür. Geliştiriciler kodlarında hiçbir değişiklik yapmadan podları uzak kümede çalıştırabilir.

### Kurulum ve Peering (Eşleştirme)

```bash
# 1. liqoctl CLI aracını kurun
curl -fsSL https://github.com/liqotech/liqo/releases/latest/download/liqoctl-linux-amd64.tar.gz | tar xzf -
sudo install -m 0755 liqoctl /usr/local/bin/liqoctl

# 2. cluster-a üzerinde Liqo'yu kurun (Pod ve Service IP bloklarını belirtin)
liqoctl install kubeadm --cluster-name cluster-a \
  --pod-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12

# 3. İki kümeyi birbirine bağlayın (cluster-a üzerinden cluster-b'ye peering başlatın)
export KUBECONFIG=cluster-a.yaml
liqoctl peer out-of-band cluster-b --kubeconfig cluster-b.yaml

# 4. Bağlantı durumunu kontrol edin
liqoctl status peer
```

### İş Yükünü Uzak Kümeye Kaydırma (Workload Offloading)

Liqo peering kurulduktan sonra, bir isim alanındaki (namespace) podların uzak kümeye de taşabilmesi için **NamespaceOffloading** kuralı tanımlanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kume_federasyonu_manifest_1.yaml](../Manifests/11_multicluster/kume_federasyonu_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Submariner: Cross-Cluster Ağ Birleşimi

**Submariner**, farklı kümelerdeki podların ve servislerin IP adreslerini birbirine doğrudan bağlayan güvenli bir VPN/Overlay ağ tüneli (IPSec veya Wireguard) oluşturur.

### Kurulum Adımları

```bash
# 1. subctl CLI aracını kurun
curl -Ls https://get.submariner.io | bash
export PATH=$PATH:~/.local/bin

# 2. Broker Cluster (Ağ metadata sunucusu) tanımlayın
subctl deploy-broker --kubeconfig broker.yaml

# 3. Cluster-A ve Cluster-B'yi bu broker'a bağlayarak ağları birleştirin:
subctl join broker-info.subm --kubeconfig cluster-a.yaml --clusterid cluster-a --cable-driver wireguard
subctl join broker-info.subm --kubeconfig cluster-b.yaml --clusterid cluster-b --cable-driver wireguard

# 4. Ağ tünellerini denetleyin
subctl show connections
```

---

## 4. MCS API: ServiceExport ile Servisleri Federasyona Açma

Submariner, Kubernetes Multi-Cluster Service (MCS) standartlarını destekler. Bir kümedeki servisi diğer kümelere açmak için **ServiceExport** nesnesi kullanılır.

```
[ Cluster A ]                                         [ Cluster B ]
  - Service: database-svc                              - nslookup database-svc.production.svc.clusterset.local
  - ServiceExport: database-svc (Kümeler arası yayın)   - Otomatik olarak ServiceImport oluşur
```

### A. Servis Yayınlama (Cluster-A üzerinde uygulanır)

```yaml
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: database-svc
  namespace: production
```

### B. Servisi Kullanma (Cluster-B üzerinde)

Uzak servise erişmek için Kubernetes-native DNS adresi (`clusterset.local`) kullanılır. Submariner Lighthouse DNS denetleyicisi bu trafiği tünel üzerinden otomatik olarak Cluster-A'ya yönlendirir:

```bash
# Cluster-B içindeki bir poddan test yapın:
kubectl run test-pod --image=busybox --rm -it --restart=Never -- \
  nslookup database-svc.production.svc.clusterset.local
```

---

## 5. Federasyon Araçları Karşılaştırma Matrisi

| Kriter | Liqo | Submariner | Karmada |
|:---|:---:|:---:|:---:|
| **Uzak Kümede Pod Çalıştırma** | ✅ Sanal Node (Virtual Kubelet) ile şeffaf | ❌ Sadece ağ birleştirir | ✅ İlke (Policy) tabanlı scheduler ile |
| **Kümeler Arası Pod IP İletişimi** | ✅ Var | ✅ Var (Overlay Tünel) | ❌ Yok (Ingress/Gateway ile) |
| **MCS (ServiceExport) Desteği** | ✅ Var | ✅ Var | ✅ Var |
| **Operasyonel Zorluk** | Orta | Orta | Yüksek (Ayrı control plane gerekir) |

> [!TIP]
> Ekipleriniz bağımsız çalışıyor ve sadece servislerin birbirleriyle konuşmasını istiyorsanız **Submariner** en sade ağ çözümüdür. Eğer sunucu kaynaklarınız yetmediğinde iş yüklerini diğer bulut/on-prem kümelerine otomatik kaydırmak istiyorsanız **Liqo** tercih edilmelidir.
