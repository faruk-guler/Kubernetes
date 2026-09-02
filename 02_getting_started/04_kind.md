# KinD (Kubernetes in Docker) ile Yerel Küme Yönetimi

**KinD** (Kubernetes IN Docker), Kubernetes kümelerini çalıştırmak için yerel Docker konteynerlerini "düğüm (node)" olarak kullanan bir araçtır. 

Öncelikli olarak Kubernetes'in kendi iç geliştirme süreçlerini (Kubernetes'in kendi kaynak kodunu test etmek) hızlandırmak için geliştirilmiş olsa da, günümüzde CI/CD hatlarında (Örn: GitHub Actions) ve yerel test ortamlarında standart haline gelmiştir.

---

## 1. Neden KinD?

- **Hız:** Saniyeler içinde sıfırdan bir küme oluşturabilirsiniz.
- **Çoklu Düğüm (Multi-Node):** Tek bir YAML konfigürasyonuyla 1 Master, 3 Worker node gibi kompleks topolojileri tek bir makinede çalıştırabilirsiniz.
- **CI/CD Dostu:** CI/CD sunucularında sanal makineye ihtiyaç duymadan, doğrudan Docker runner'ı içinde K8s çalıştırılabilmesini sağlar.
- **Upstream Uyumluluk:** Kubernetes kod tabanıyla birebir uyumlu, CNCF uyumlu (conformant) bir sürümdür.

---

## 2. KinD Kurulumu

KinD'in çalışması için bilgisayarınızda **Docker** veya **Podman** kurulu ve çalışır durumda olmalıdır.

### Windows (winget ile)
```powershell
winget install Kubernetes.kind
```

### Linux (curl ile)
```bash
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### macOS (Homebrew ile)
```bash
brew install kind
```

---

## 3. Küme Oluşturma ve Yönetme

### Hızlı Başlangıç (Tek Düğüm)
En basit haliyle, hiçbir yapılandırma dosyası belirtmeden varsayılan bir küme oluşturmak için:
```bash
kind create cluster
```
*Bu komut, K8s imajını indirir, düğümü başlatır ve yerel `~/.kube/config` dosyanızı otomatik olarak günceller.*

### Kümeleri Listeleme
```bash
kind get clusters
```

### Kümeyi Silme
```bash
kind delete cluster --name kind
```
*(Varsayılan küme adı `kind`'dır)*

---

## 4. Gelişmiş Topolojiler (Çoklu Düğüm)

KinD'in gerçek gücü, YAML yapılandırmalarıyla çoklu düğümlü (multi-node) kümeler simüle edebilmesidir.

Aşağıdaki içeriği `kind-config.yaml` olarak kaydedin (1 Control Plane, 2 Worker):

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
```

Bu yapılandırmayla küme oluşturmak için:
```bash
kind create cluster --config kind-config.yaml --name multi-node-cluster
```

Oluşan düğümleri kontrol edin:
```bash
kubectl get nodes
```
Çıktıda 3 farklı düğüm (1 master, 2 worker) göreceksiniz. Hepsi arka planda bilgisayarınızda çalışan Docker konteynerleridir.

---

## 5. Port Yönlendirme ve Ingress Yapılandırması

KinD, sanal düğümlerini dış dünyadan izole eder. Eğer Ingress Controller kuracaksanız (örneğin NGINX), `kind-config.yaml` dosyasında yerel bilgisayarınızın portlarını (80 ve 443), konteynerlere bind (bağlama) etmeniz gerekir:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
```

---

## 6. Yerel İmajları KinD'e Yüklemek

Tıpkı Minikube'da olduğu gibi, bilgisayarınızda `docker build` ile oluşturduğunuz bir imajı, KinD düğümleri otomatik olarak çekemez.

İmajı doğrudan KinD kümenize yüklemek için:
```bash
kind load docker-image benim-uygulamam:v1.0.0 --name kind
```

## Özet
**KinD**, özellikle CI/CD hatlarında (GitHub Actions vb.) E2E (uçtan uca) testler koşmak ve geliştirici bilgisayarlarında çok düğümlü kümeleri simüle etmek için endüstri standardı haline gelmiştir. 
Minikube'un eklentilerle (addon) sağladığı kolaylıklara sahip olmasa da, saf (pure) Kubernetes deneyimi ve hızı açısından rakipsizdir.
