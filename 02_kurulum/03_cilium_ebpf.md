# Cilium eBPF — CNI Kurulumu ve Yapılandırması

Cilium, 2026 Kubernetes standartlarının temel ağ bileşenidir. `kube-proxy` yerine eBPF kullanarak çok daha yüksek performans ve görünürlük sağlar.

## 3.1 Cilium Neden?

| Özellik | iptables / kube-proxy | Cilium eBPF |
|:---|:---:|:---:|
| Performans | Orta | Çok Yüksek |
| Ağ görünürlüğü | Düşük | Tam (Hubble) |
| Network Policy | Temel L3/L4 | L3/L4/L7 + DNS |
| Service Mesh | Hayır | Opsiyonel (Sidecar'sız) |
| Gateway API | Hayır | Evet (Native) |
| Multi-cluster | Hayır | Evet (ClusterMesh) |

## 3.2 Cilium CLI Kurulumu

```bash
# Güncel sürümü bul
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)

# İndir ve kurulum yap
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz

tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz

# Doğrulama
cilium version --client
```

## 3.3 Cilium Kurulumu (kube-proxy Değişimi)

```bash
# <MASTER_IP> yerine master node'un dahili IP adresini yazın
cilium install --version 1.16.0 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<MASTER_IP> \
  --set k8sServicePort=6443
```

### Kurulum Doğrulama

```bash
# Tüm bileşenlerin hazır olmasını bekle
cilium status --wait

# Bağlantı testi
cilium connectivity test
```

Çıktıda tüm satırlar `✅ OK` görünmelidir. Node'lar artık `Ready` durumuna geçer:

```bash
kubectl get nodes
# NAME             STATUS   ROLES           AGE   VERSION
# k8s-master-01   Ready    control-plane   5m    v1.32.0
# k8s-worker-01   Ready    <none>          3m    v1.32.0
```

## 3.4 Hubble — Ağ Gözlemlenebilirliği

Cilium'un görünürlük katmanı olan Hubble'ı etkinleştirin:

```bash
# Hubble'ı etkinleştir (UI dahil)
cilium hubble enable --ui

# Hubble CLI kurulumu
export HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --fail --remote-name-all \
  https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz
tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin
rm hubble-linux-amd64.tar.gz

# Ağ trafiğini canlı izle
hubble observe --pod my-app-pod -f

# Belirli bir protocole göre filtrele
hubble observe --protocol http --output flow
```

## 3.5 Gateway API Desteğini Etkinleştirme

```bash
# Önce Gateway API CRD'lerini kur
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Cilium'u Gateway API desteğiyle güncelle
cilium upgrade --set gatewayAPI.enabled=true

# Doğrulama
kubectl get gatewayclass
# NAME     CONTROLLER                     ACCEPTED
# cilium   io.cilium/gateway-controller   True
```

## 3.6 Cilium ClusterMesh (Multi-Cluster)

Birden fazla cluster'ı ağ düzeyinde birleştirmek için:

```bash
# Her cluster'da etkinleştir
cilium clustermesh enable --service-type LoadBalancer

# Cluster'ları birbirine bağla
cilium clustermesh connect --destination-context=<diger-cluster-context>

# Durum kontrolü
cilium clustermesh status --wait
```

> [!TIP]
> Cilium'un Direct Routing modunu etkinleştirmek, VXLAN encapsulation'a kıyasla ağ performansını %20-30 artırır: `--set routingMode=native --set autoDirectNodeRoutes=true`

