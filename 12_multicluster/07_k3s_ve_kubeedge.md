# Uç Bilişim (Edge Computing): K3s ve KubeEdge Mimarisi

Bulut yerli (cloud-native) mimarilerin sınırları artık sadece devasa veri merkezleriyle sınırlı değildir. 2026 yılı altyapı standartlarında Kubernetes; akıllı fabrikalarda, hastanelerde, otonom araçlarda, perakende mağazalarında ve kısıtlı donanımlara sahip IoT (Nesnelerin İnterneti) cihazlarında da çalıştırılmaktadır. Uç bilişim (**Edge Computing**) dünyasında en temel zorluklar: kısıtlı donanım kaynakları (512MB-2GB RAM), kesintili internet bağlantıları ve binlerce bağımsız lokasyonun otonom çalışmasıdır.

Bu zorlukları çözmek için geliştirilen iki temel teknolojiyi inceleyeceğiz: **K3s** ve **KubeEdge**.

---

## 1. K3s: Hafifletilmiş Kubernetes Dağıtımı

Rancher tarafından geliştirilen ve şu an CNCF projesi olan **K3s**, kaynak tüketimi optimize edilmiş, tüm Kubernetes bileşenlerini tek bir binary dosyası içinde birleştiren hafif bir Kubernetes dağıtımıdır.

| Karşılaştırma Kriteri | K3s Dağıtımı | Standart Kubernetes (K8s) |
| :--- | :---: | :---: |
| **Binary Paket Boyutu** | ~70 MB | ~1 GB+ |
| **Minimum RAM Tüketimi** | 512 MB+ | 2 GB+ |
| **Veritabanı Katmanı** | SQLite (Varsayılan) / etcd | etcd (Zorunlu) |
| **Yerleşik Ağ Katmanı (CNI)** | Flannel | Yok (Manuel kurulur) |
| **Yerleşik Ingress** | Traefik | Yok |

### K3s Sunucu (Server) Kurulumu

Bu rehberde **Cilium CNI ve Gateway API** yapısı hedeflendiği için K3s'in yerleşik Traefik, ServiceLB ve Flannel CNI özellikleri devre dışı bırakılarak kurulum yapılır:

```bash
# 1. K3s Master Kurulumu (Traefik, ServiceLB ve Flannel iptal edilerek)
curl -sfL https://get.k3s.io | sh -s - \
  --disable=traefik \
  --disable=servicelb \
  --flannel-backend=none \
  --disable-network-policy

# 2. Erişim yetkilerini ayarlayın
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. K3s üzerine Cilium CNI kurulumunu başlatın:
cilium install --version 1.16.0 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.1.50 \
  --set k8sServicePort=6443
```

### K3s İşçi (Worker/Agent) Düğüm Ekleme

```bash
# 1. Ana sunucudan katılım anahtarını (Token) alın:
cat /var/lib/rancher/k3s/server/node-token

# 2. Uzak Edge cihaz üzerinde agent kurulumunu başlatın:
curl -sfL https://get.k3s.io | K3S_URL=https://<MASTER_IP>:6443 K3S_TOKEN=<TOKEN> sh -
```

---

## 2. KubeEdge: Bulut-Cihaz Entegrasyonu

Kümelerin doğrudan internete açık olmadığı veya binlerce cihazın tek bir Kubernetes API sunucusu üzerinden otonom yönetilmesi gereken durumlarda **KubeEdge** devreye girer.

```text
[ Bulut Kümesi (CloudCore) ]
            │
            ▼ (Güvenli WebSocket / Quic Tüneli)
[ Uç Cihazlar / IoT (EdgeCore) ]
  ├── ContainerD (Konteyner Çalışma Zamanı)
  ├── EdgeMesh (Cihazlar arası yerel servis keşfi)
  └── Podlar (İnternet kopsa dahi çalışmaya devam eder)
```

* **Çevrimdışı Çalışma (Offline Mode):** İnternet kesilse dahi uçtaki podlar çalışmaya, cihazlar veri üretmeye devam eder. Bağlantı geldiğinde durum bulut ile eşitlenir.
* **EdgeMesh:** Cihazların bulut kontrol düzlemine (API Server) ihtiyaç duymadan yerel ağ üzerinden birbiriyle konuşmasını sağlar.

---

## 3. Uç Noktalar İçin Esnek Pod Dağıtım Şablonu

Edge cihazlar sıklıkla geçici bağlantı kayıpları yaşar. Kubernetes'in normal şartlarda bir podu `NotReady` olan node'dan hemen tahliye etme (eviction) davranışını engellemek ve podun edge node'unda kalmasını sağlamak için toleration değerleri yüksek tutulur:

```yaml
tolerations:
  - key: "node.kubernetes.io/unreachable"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 6000 # Bağlantı kopsa dahi podu 100 dakika tahliye etme
  - key: "node.kubernetes.io/not-ready"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 6000
```

---

## 4. WebAssembly (WASM) ile Uç Cihazlarda Kod Çalıştırma (2026 Standartları)

512MB RAM'e sahip çok küçük sensör kartlarında (IoT) standart Docker konteynerleri dahi ağır çalışır. 2026 yılı standartlarında uç cihazlarda konteyner alternatifi olarak **WASM (WebAssembly)** iş yükleri doğrudan K3s/KubeEdge üzerinde koşturulur. WASM podları milisaniyeler içinde açılır ve sadece birkaç megabayt RAM harcar.

WASM iş yüklerini kümede çalıştırabilmek için önce sisteme uygun bir **RuntimeClass** (çalışma zamanı sınıfı) tanımlanır.

### A. WASM `RuntimeClass` Tanımı

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: wasm-spin
# Uzak düğümlerdeki spin runtime shim modülünü tetikleyin:
handler: spin
```

### B. WASM Pod Tanımı

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: iot-sensor-wasm-pod
  namespace: edge-system
spec:
  runtimeClassName: wasm-spin
  containers:
    - name: sensor-telemetry
      image: ghcr.io/company/iot-spin-sensor:v1.0.0
      command: ["/"]
      resources:
        limits:
          memory: 32Mi
          cpu: 100m
```
