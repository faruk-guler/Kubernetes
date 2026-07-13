# vCluster — Sanal Kubernetes Kümeleri (Virtual Clusters)

Büyük ölçekli Kubernetes altyapılarında, farklı ekipler veya projeler için ayrı fiziksel kümeler (physical clusters) kurmak ve yönetmek hem maliyet hem de operasyonel yük açısından sürdürülemez bir durumdur. Diğer taraftan, tek bir kümede sadece namespace-bazlı yalıtım (RBAC, NetworkPolicy vb.) kullanmak da tam izolasyon sağlamaz. Özellikle Custom Resource Definition (CRD) yönetimi, global API nesneleri ve küme genelinde yetki gereksinimi duyan iş yükleri söz konusu olduğunda namespace sınırları aşılır.

**vCluster (Virtual Clusters)**, mevcut bir fiziksel Kubernetes kümesi (Host Cluster) üzerinde tamamen izole, bağımsız ve hafif (lightweight) sanal kümeler oluşturulmasını sağlar. Her sanal küme kendi API Server'ına, etcd veri tabanına ve denetleyicilerine (controllers) sahiptir, ancak host kümedeki düğümleri (nodes) ve kaynakları paylaşımlı olarak kullanır.

---

## 1. Neden vCluster?

vCluster, fiziksel küme kurulumunun getirdiği yüksek maliyetler ile namespace yalıtımının getirdiği güvenlik/yönetilebilirlik sınırları arasında mükemmel bir denge sunar.

```
Fiziksel / Host Küme (AKS, EKS, GKE, On-Premise)
  ├── vcluster-dev-1 (Namespace)
  │     └── [Sanal API Server + etcd] ──► Pod'lar (Host üzerinde çalışır)
  ├── vcluster-test-1 (Namespace)
  │     └── [Sanal API Server + etcd] ──► Pod'lar (Host üzerinde çalışır)
  └── vcluster-prod-1 (Namespace)
        └── [Sanal API Server + etcd] ──► Pod'lar (Host üzerinde çalışır)
```

### Temel Kullanım Senaryoları

* **CI/CD İş Akışları (Ephemeral Clusters):** Her Pull Request (PR) için sıfırdan sanal bir Kubernetes kümesi oluşturulup testler bittikten sonra saniyeler içinde silinmesi.
* **Çok Ekipli (Multi-Tenant) Geliştirme:** Ekiplerin birbirlerinin kaynaklarını, CRD'lerini veya API yapılandırmalarını bozmadan kendi admin yetkileriyle çalışması.
* **Eğitim ve Sandbox Ortamları:** Kullanıcılara gerçek bir Kubernetes kümesi gibi davranan, ancak host kümenin güvenliğini ve stabilitesini riske atmayan yalıtılmış çalışma alanları sunma.

---

## 2. vCluster Mimari Yapısı

Bir vCluster, host kümedeki tek bir namespace içerisinde çalışır. İçerisinde şu üç temel bileşen bulunur:

1. **k3s (veya k8s):** vCluster varsayılan olarak API Server, Controller Manager ve depolama için gömülü sqlite/etcd barındıran hafif bir k3s yapısı kullanır.
2. **Syncer (Senkronize Edici):** vCluster içindeki kaynakları (Pod, Service, PVC, ConfigMap vb.) izler ve bunları host kümedeki ilgili namespace'e senkronize eder. Böylece podlar aslında host kümenin konteyner çalışma zamanı (containerd/docker) tarafından çalıştırılır.
3. **Virtual API Server:** Geliştiriciler veya CI/CD araçları doğrudan bu sanal API Server ile konuşur. Böylece ana kümenin API Server yükü artmaz.

---

## 3. Kurulum ve Kullanım

### vCluster CLI Kurulumu

Sanal kümeleri kolayca yönetmek için yerel makinenize `vcluster` CLI aracını kurun:

```bash
# Linux/macOS için:
curl -L -o vcluster https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64
chmod +x vcluster
sudo mv vcluster /usr/local/bin/

# Windows (PowerShell) için:
# iwr -useb https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-windows-amd64.exe -OutFile vcluster.exe
```

### Sanal Küme Oluşturma

Host kümenize bağlı durumdayken yeni bir vCluster oluşturun:

```bash
# "team-alpha" adında ve "vcluster-team-alpha" isim alanında sanal küme oluşturun
vcluster create team-alpha --namespace vcluster-team-alpha --create-namespace
```

### Bağlantı ve Yönetim

Sanal kümeye bağlanmak için:

```bash
# vCluster'a güvenli bir tünel açarak kubeconfig dosyanızı güncelleyin
vcluster connect team-alpha -n vcluster-team-alpha

# Artık bu terminalde çalıştıracağınız kubectl komutları doğrudan vCluster'a gider:
kubectl get nodes
kubectl get ns
kubectl get pods -A
```

*Not: `kubectl get nodes` çalıştırdığınızda, host kümedeki düğümler sanal olarak görünür, ancak bu düğümler üzerinde değişiklik yapamazsınız.*

---

## 4. Yapılandırma (`values.yaml`)

vCluster, Helm tabanlı olarak dağıtılır. Özelleştirilmiş kurulumlar için bir `values.yaml` dosyası hazırlayabilirsiniz. Örneğin, sanal kümenin SQLite yerine harici bir etcd kullanması, host kümedeki StorageClass'ları veya Ingress'leri senkronize etmesi sağlanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [vcluster_manifest_1.yaml](../Manifests/11_multicluster/vcluster_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu yapılandırma ile vCluster oluşturmak için:

```bash
vcluster create team-alpha -n vcluster-team-alpha -f vcluster-values.yaml
```

---

## 5. GitOps ile vCluster (ArgoCD)

Sanal kümelerin kendilerini de GitOps prensipleriyle yönetebilirsiniz. ArgoCD kullanarak bildirimsel olarak bir vCluster ayağa kaldırmak için aşağıdaki gibi bir Helm Application tanımı yapabilirsiniz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [vcluster_manifest_2.yaml](../Manifests/11_multicluster/vcluster_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. CI/CD: PR Başına Geçici vCluster

CI/CD boru hatlarında testlerin yalıtılmış ve temiz bir ortamda çalışması kritik önem taşır. GitHub Actions üzerinde PR açıldığında geçici bir vCluster oluşturup testi koşturan örnek bir adım:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [vcluster_manifest_3.yaml](../Manifests/11_multicluster/vcluster_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. Yönetim Komutları ve Maliyet Tasarrufu

vCluster, bulut faturalarını düşürmek için harika bir "duraklatma/devam ettirme (pause/resume)" mekanizmasına sahiptir. Kullanılmayan test kümelerini duraklatarak CPU ve bellek tüketimini sıfıra indirebilirsiniz.

```bash
# Tüm aktif vCluster'ları listele
vcluster list

# Bir sanal kümeyi duraklat (tüm sanal podlar ve kontrol bileşenleri 0 replikaya düşürülür)
vcluster pause team-alpha --namespace vcluster-team-alpha

# Sanal kümeyi tekrar aktif et (eski haline geri döner, veri kaybı olmaz)
vcluster resume team-alpha --namespace vcluster-team-alpha

# vCluster ve ona ait tüm kaynakları (PVC'ler dahil) temizle
vcluster delete team-alpha --namespace vcluster-team-alpha
```

---

## 8. Karşılaştırma Tablosu

Sanal kümelerin geleneksel yöntemlerle karşılaştırılması:

| Özellik | İsim Alanı (Namespace) | Sanal Küme (vCluster) | Fiziksel Küme (Physical) |
| :--- | :--- | :--- | :--- |
| **İzolasyon Derecesi** | Düşük (Sadece mantıksal) | **Yüksek (Kendi API & Etcd)** | Tam donanımsal/sanal |
| **Maliyet ve Kaynak** | Çok Düşük (Ek yük yok) | **Çok Düşük (K3s ek yükü minimal)** | Yüksek (Control plane maliyeti) |
| **Kendi CRD Tanımları** | Hayır (Host CRD'lerini kullanır) | **Evet (Bağımsız CRD kurabilir)** | Evet |
| **Kendi RBAC Kuralları** | Sınırlı (Namespace düzeyinde) | **Evet (Sanal küme içinde ClusterRole)** | Evet |
| **Kurulum Hızı** | Milisaniyeler | **Saniyeler (~30 sn)** | Dakikalar (~10-15 dk) |
| **Cluster Admin Yetkisi** | Hayır (Küme genelinde tehlikeli) | **Evet (Sanal küme içinde Admin)** | Evet |
