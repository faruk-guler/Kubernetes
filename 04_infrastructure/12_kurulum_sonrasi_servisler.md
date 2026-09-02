# Kurulum Sonrası Servisler ve Eklentiler (Post-Installation Services)

Yalın (Vanilla) bir Kubernetes kümesi kurulduktan sonra, sadece temel konteyner yönetimi yeteneklerine sahiptir. Kümeyi üretim ortamlarında (production) verimli ve güvenli bir şekilde çalıştırabilmek, kalıcı veri saklayabilmek ve otomatik ölçeklendirme yapabilmek için kurulum sonrasında belirli çekirdek servislerin eklenmesi gerekir.

Bu bölümde, küme kurulumunun hemen ardından kurulması standart kabul edilen 5 temel eklentiyi ve kurulum adımlarını ele alacağız: **Helm**, **Rancher**, **Longhorn**, **NeuVector** ve **Metrics Server**.

---

## 1. Helm — Kubernetes Paket Yöneticisi

Linux işletim sistemleri için `apt` veya `dnf` ne ise, Kubernetes için **Helm** odur. Uygulamalarınızı tek bir şablon paket halinde paketlemenizi ve tek komutla güncellemenizi sağlar.

```bash
# 1. Resmi kurulum scriptini indirin ve çalıştırın
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 2. Kurulumu doğrulayın
helm version
```

---

## 2. Rancher — Merkezi Çoklu Küme Yönetimi

**Rancher**, kümenizi görsel olarak yönetmek, kullanıcı erişimlerini sınırlamak (SSO/RBAC) ve birden fazla Kubernetes kümesini tek bir panelden kontrol etmek için kurumsal standarttır.

Rancher kurulmadan önce SSL/TLS yönetimini üstlenen **cert-manager** kurulmalıdır:

```bash
# 1. cert-manager kurulumu (Helm OCI Deposu Üzerinden)
helm install cert-manager \
  oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true

# 2. Rancher Helm deposunu ekleyin ve güncelleyin
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# 3. Rancher web arayüzünü kendi domain adınızla kurun
helm upgrade -i rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=RancherSifresi123 \
  --set replicas=1
```

---

## 3. Longhorn — Dağıtık ve Kalıcı Depolama (Distributed Storage)

Kubernetes üzerinde koşan veritabanı gibi durumlu (stateful) uygulamaların disk verilerini yedekli ve yüksek erişilebilir (HA) şekilde saklamak için distributed block storage aracı olan **Longhorn** kurulur.

```bash
# 1. Longhorn deposunu ekleyin ve güncelleyin
helm repo add longhorn https://charts.longhorn.io
helm repo update

# 2. Longhorn'u kümenize kurun
helm upgrade -i longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace
```

*Not: Longhorn'un çalışabilmesi için tüm worker düğümlerinde `open-iscsi` paketinin kurulu olması gerekir (`sudo apt install open-iscsi`).*

---

## 4. NeuVector — Gerçek Zamanlı Konteyner Güvenliği

**NeuVector**, SUSE tarafından geliştirilen, küme içi ağ trafiğini katman 7 (L7) seviyesinde inceleyen, gerçek zamanlı konteyner güvenlik duvarı (Firewall) ve zafiyet tarama servisidir.

```bash
# 1. NeuVector deposunu ekleyin
helm repo add neuvector https://neuvector.github.io/neuvector-helm/ --force-update

# 2. NeuVector'ü web paneline NodePort ile dışarıdan erişecek şekilde kurun
helm upgrade -i neuvector --namespace cattle-neuvector-system neuvector/core \
  --create-namespace \
  --set manager.svc.type=NodePort \
  --set controller.pvc.enabled=true
```

---

## 5. Metrics Server — Temel Kaynak İzleme

Metrics Server, kümedeki düğümlerin ve podların anlık CPU/RAM kullanımlarını toplayan hafif bir servistir. Bu servis olmadan `kubectl top` komutları çalışmaz ve podların yüke göre otomatik ölçeklenmesini sağlayan **HPA (Horizontal Pod Autoscaler)** çalıştırılamaz.

```bash
# 1. Metrics Server bileşenlerini kurun
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### ⚠️ Önemli: Test ve Laboratuvar Ortamlarında TLS Hatasını Aşma

Eğer sunucularınızda kendi kendine imzalanmış (self-signed) SSL sertifikaları kullanılıyorsa, Metrics Server güvenli olmayan sertifika hatası verir. Bu sorunu aşmak için Metrics Server deployment'ına güvensiz TLS bayrağını eklemeniz gerekir:

```bash
# 1. Metrics Server deployment'ını düzenleyin
kubectl edit deployment metrics-server -n kube-system

# 2. spec.template.spec.containers[0].args dizisine şu parametreyi ekleyin:
# - --kubelet-insecure-tls
```

Ekledikten sonra doğrulamak için:

```bash
# Birkaç dakika sonra CPU/RAM metriklerini kontrol edin
kubectl top nodes
kubectl top pods -A
```

---

## Özet

Yalın Kubernetes kurulumunun ardından **Helm** ile paket yönetimine kavuşulur. **Metrics Server** ile kümenin anlık kaynak izlemesi (top) ve otomatik ölçekleme yeteneği açılır. **Longhorn** ile veri kayıplarını önleyen dağıtık disk yapısı oluşturulurken, **Rancher** tüm bu ekosistemi tek bir merkezi görsel panelden yönetmenizi sağlar.
