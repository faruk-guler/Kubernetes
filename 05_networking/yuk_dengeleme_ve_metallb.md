# Yük Dengeleme ve MetalLB (Load Balancing & MetalLB)

Bulut sağlayıcılarında (AWS, GCP, Azure) çalışan yönetilen Kubernetes servislerinde `type: LoadBalancer` tipinde bir Service oluşturduğunuzda, arka planda bulutun yerel yük dengeleyicisi (ALB, NLB, ALB vb.) otomatik olarak oluşturulur ve servise atanır. Ancak bare-metal (şirket içi - on-premise) Kubernetes kurulumlarında bu otomasyon yoktur ve oluşturulan yük dengeleyiciler sonsuza kadar `<pending>` durumunda kalır. **MetalLB**, bu sorunu çözerek bare-metal kümelere yük dengeleme yeteneği kazandırır.

---

## 1. Neden MetalLB?

| Küme Ortamı | Yük Dengeleme Sağlayıcısı |
| :--- | :--- |
| **AWS EKS** | AWS Network/Application Load Balancer |
| **GCP GKE** | Google Cloud Load Balancer |
| **On-Premise (Bare-Metal)** | **MetalLB** (Manuel Kurulum) |
| **Yerel Ortam (Kind / k3d)** | **MetalLB** (Lab Yapılandırması) |

---

## 2. MetalLB Çalışma Modları

MetalLB, dış ağ trafiğini worker düğümlerine yönlendirmek için iki farklı çalışma modu sunar:

### A. Layer 2 Modu (ARP/NDP)

* **Nasıl Çalışır:** Kümedeki worker düğümlerinden biri lider seçilir ve dış dünyadan gelen ARP (IPv4 için Address Resolution Protocol) isteklerine kendi MAC adresini dönerek IP'yi sahiplenir. Tüm dış trafik bu tek düğüm üzerinden akar.
* **Failover:** Lider düğüm çökerse, başka bir düğüm saniyeler içinde liderliği devralır ve yeni bir ARP duyurusu yapar.
* **Sınırlama:** Gerçek bir yük dengeleme (load balancing) sağlamaz, trafik tek bir düğümde toplanarak darboğaz (bottleneck) oluşturabilir.

### B. BGP Modu (Border Gateway Protocol)

* **Nasıl Çalışır:** Kümedeki tüm worker düğümleri, dış dünyadaki fiziksel switch veya router'lar ile BGP protokolü üzerinden komşuluk kurar.
* **Yük Dengeleme:** Gelen trafik, Switch üzerindeki ECMP (Equal-Cost Multi-Path) algoritması kullanılarak tüm düğümlere eşit ağırlıkta dağıtılır.
* **Üretim Ortamı:** Gerçek yük dengeleme sağladığı için üretim (production) ortamları için önerilen standarttır.

---

## 3. MetalLB Kurulumu

MetalLB manifestolarını ve CRD'lerini kümeye uygulamak için:

```bash
# 1. MetalLB bileşenlerini ve denetleyicilerini kurun
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# 2. Podların hazır duruma gelmesini bekleyin
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

---

## 4. Layer 2 Yapılandırması (Configuration)

MetalLB'nin çalışabilmesi için dış IP adresi dağıtacağı bir IP havuzu ve bunu L2 (ARP) ile duyuracak bir kural tanımlanmalıdır.

### A. IPAddressPool Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [yuk_dengeleme_ve_metallb_manifest_1.yaml](../Manifests/05_networking/yuk_dengeleme_ve_metallb_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. L2Advertisement Tanımı

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - production-ip-pool # Yukaradaki havuz ilişkilendirilir
```

---

## 5. Servis Üzerinde Kullanımı

MetalLB yapılandırıldıktan sonra, oluşturulan LoadBalancer servislerine havuzdan otomatik IP atanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [yuk_dengeleme_ve_metallb_manifest_2.yaml](../Manifests/05_networking/yuk_dengeleme_ve_metallb_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Teşhis ve Sorun Giderme (Troubleshooting)

IP atanamaması durumunda izlenecek adımlar:

```bash
# 1. Controller ve Speaker loglarını kontrol edin
kubectl logs -n metallb-system -l component=controller
kubectl logs -n metallb-system -l component=speaker

# 2. Servis durumunu kontrol edin (EXTERNAL-IP atandı mı?)
kubectl get svc -n production

# 3. ARP tablosunu kontrol edin (Düğüm üzerinde)
arp -n | grep <assigned-external-ip>
```
