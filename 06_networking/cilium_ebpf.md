# Cilium ve eBPF Mimarisi

**Cilium**, Linux çekirdeğinin (kernel) içinde çalışan devrimsel **eBPF (Extended Berkeley Packet Filter)** teknolojisini temel alan, Kubernetes için yüksek performanslı ve güvenli bir CNI (Container Network Interface) projesidir. CNCF Graduated statüsünde olan Cilium, 2026 yılı standartlarında hantal ve yavaş olan geleneksel `kube-proxy` ve `iptables` ağ yönlendirme modelini tamamen rafa kaldırmıştır.

---

## 1. Neden Cilium ve eBPF?

Geleneksel Kubernetes ağ yönetiminde, her yeni Service eklendiğinde `kube-proxy` düğümler üzerindeki `iptables` kurallarını doğrusal (linear) olarak yazar. Büyük kümelerde (10.000+ kural) her paket bu kuralları tek tek taramak zorunda kalır ve ağ gecikmesi (latency) katlanarak artar.

Cilium ve eBPF ise ağ yönlendirmelerini kernel düzeyinde **Hash Tabloları (BPF Maps)** kullanarak **O(1) sabit sürede** gerçekleştirir.

```
Geleneksel Model (kube-proxy + iptables):
  Pod ──► iptables kurallarında doğrusal tarama (10.000+ kural) ──► Yavaş

Cilium Modeli (eBPF):
  Pod ──► Hash tablosundan anında hedef bulma (O(1) lookup) ──► Çok Hızlı
```

---

## 2. Cilium Kurulumu (kube-proxy Yerine)

Kümeyi kurarken `kube-proxy` addon'ını es geçip doğrudan Cilium'u onun yerine konumlandırarak (KubeProxyReplacement) kurmak en temiz yöntemdir:

```bash
# 1. Cilium Helm deposunu ekleyin
helm repo add cilium https://helm.cilium.io/
helm repo update

# 2. kubeProxyReplacement aktif olacak şekilde kurulumu başlatın
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<CONTROL_PLANE_IP> \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

Sistem kurulduktan sonra durumu sorgulayın:

```bash
# Cilium durumunu doğrulama
cilium status
```

---

## 3. Hubble ile Ağ Gözlemlenebilirliği (Network Observability)

Cilium'un eBPF gücü, ağ trafiğini ek bir sidecar veya proxy kurmadan kernel düzeyinde dinleyen **Hubble** bileşeniyle birleşir. Hubble, ağ akışlarını (flows) görselleştirir ve analiz eder.

```bash
# 1. Hubble CLI aracını indirin ve kurun
export HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all "https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz"
tar xzvf hubble-linux-amd64.tar.gz
sudo mv hubble /usr/local/bin/

# 2. Hubble Relay tünelini açın
cilium hubble port-forward &

# 3. Canlı ağ trafiğini izlemeye başlayın
hubble observe --follow

# 4. Sadece engellenen (dropped) paketleri izleme (Ağ hatası tespiti)
hubble observe --verdict DROPPED
```

---

## 4. CiliumNetworkPolicy (L7 Koruması)

Standart Kubernetes NetworkPolicy nesneleri sadece L3 (IP) ve L4 (Port) düzeyinde kısıtlama yapabilirken, Cilium L7 (HTTP / gRPC) düzeyinde politikaları destekler:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cilium_ebpf_manifest_1.yaml](../Manifests/05_networking/cilium_ebpf_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Teşhis ve Hata Ayıklama (Troubleshooting)

```bash
# 1. Cilium podu içinden genel durumu sorgulama
kubectl -n kube-system exec -it ds/cilium -- cilium status --verbose

# 2. Küme içi uç noktaları (endpoints) listeleme
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list

# 3. Kapsamlı ağ bağlantı testi koşturma (CNI testi)
cilium connectivity test
```
