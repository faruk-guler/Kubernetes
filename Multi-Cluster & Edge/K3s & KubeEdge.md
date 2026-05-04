# Edge Computing: K3s ve KubeEdge

## Edge Kubernetes Neden Gerekli?

2026'da Kubernetes yalnızca veri merkezlerinde değil, fabrikalarda, hastanelerde, araçlarda ve IoT cihazlarında çalışır. Edge'de temel zorluklar:

- Kısıtlı CPU/RAM (512MB - 2GB)
- Güvenilmez internet bağlantısı
- Offline çalışma zorunluluğu
- Yüzlerce/binlerce cihaz yönetimi

## K3s — Hafif Kubernetes

K3s, kaynak kullanımı optimize edilmiş, tek bir binary dosyası olarak çalışan ve 2026'da Edge'in standardı olan bir Kubernetes dağıtımıdır.

| Özellik | K3s | Standart K8s |
|:---|:---:|:---:|
| Binary boyutu | ~70MB | ~1GB+ |
| RAM kullanımı | 512MB+ | 2GB+ |
| etcd | SQLite (opsiyonel) | etcd (varsayılan) |
| Dahili CNI | Flannel | Yok |
| Dahili Ingress | Traefik | Yok |

### K3s Kurulumu

```bash
# K3s server kurulumu
# NOT: Bu rehber Cilium + Gateway API kullandığı için Traefik devre dışı bırakılır
curl -sfL https://get.k3s.io | sh -s - \
  --disable=traefik \
  --disable=servicelb \
  --flannel-backend=none \
  --disable-network-policy

# kubeconfig ayarı
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Cilium kurulumu (K3s üzerinde)
cilium install --version 1.16.0 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<K3S_IP> \
  --set k8sServicePort=6443
```

> [!WARNING]
> K3s varsayılan olarak **Traefik** ve **ServiceLB** ile gelir. Bu rehberdeki Cilium + Gateway API yapısıyla çakışır. `--disable=traefik --disable=servicelb` ile devre dışı bırakıp Cilium kurmanız **zorunludur**.

### K3s Worker Ekleme

```bash
# Server token'ı al
cat /var/lib/rancher/k3s/server/node-token

# Edge cihazda agent kurulumu
curl -sfL https://get.k3s.io | K3S_URL=https://<SERVER_IP>:6443 K3S_TOKEN=<TOKEN> sh -
```

## KubeEdge — Binlerce Cihaz Yönetimi

Eğer çok sayıda Edge cihazınız varsa, **KubeEdge** merkezi yönetim sağlar:

```
Cloud Cluster (KubeEdge CloudCore)
        │
        │ WebSocket / HTTP
        │
Edge Cihaz (KubeEdge EdgeCore)
  ├── ContainerD
  └── Pod'lar (Offline'da da çalışır)
```

**KubeEdge özellikleri:**
- **Offline Mode:** İnternet kesilse bile Edge cihazlar çalışmaya devam eder
- **EdgeMesh:** Cihazlar arası servis keşfi (cloud API olmadan)
- **Device Management:** IoT cihaz twin'leri (shadow) yönetimi

## Edge Deployment Örneği

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: temperature-sensor
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/edge: "true"    # Edge node'lara gönder
        location: factory-floor-a               # Belirli lokasyon
      tolerations:
      - key: "node.kubernetes.io/unreachable"   # Offline durumu tolere et
        operator: Exists
        effect: NoExecute
        tolerationSeconds: 3600
      containers:
      - name: sensor-app
        image: my-edge-registry/temp-sensor:v2.0.0
        resources:
          limits:
            cpu: "200m"
            memory: "64Mi"    # Edge için minimal kaynak
```

## WASM — Edge'in Geleceği (2026)

2026'da Edge'de **WebAssembly (WASM)** container alternatifi olarak yaygınlaşmaktadır:

```yaml
# WASM pod örneği (CRI-Wasm gerektirir)
apiVersion: v1
kind: Pod
metadata:
  name: wasm-sensor
  annotations:
    module.wasm.image/variant: compat-smart
spec:
  runtimeClassName: crun        # WASM runtime
  containers:
  - name: sensor
    image: my-registry/sensor:wasm
    # WASM avantajları: 2-5ms başlama süresi, 1/10 bellek kullanımı
```

> [!TIP]
> WASM, özellikle start-up süresi kritik olan Edge senaryolarda büyük avantaj sağlar. Knative + WASM kombinasyonu, Scale-to-Zero süresini saniyelerden milisaniyelere düşürür.
