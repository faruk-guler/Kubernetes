# Cluster API (CAPI) ile Bildirimsel Kubernetes Küme Yönetimi

Kubernetes kümesi üzerinde uygulamaları yönetirken kullandığımız bildirimsel (declarative) modelin aynısını, kümelerin kendi yaşam döngüleri (oluşturma, güncelleme, silme) için de kullanmak bulut yerli (cloud-native) mimarinin en uç noktasıdır. **Cluster API (CAPI)**, "Kubernetes ile Kubernetes yönetmek" felsefesine dayanır. Bir "Yönetici Küme (Management Cluster)", CAPI denetleyicileri sayesinde AWS, Azure, GCP veya VMware üzerinde bağımsız "İş Yükü Kümelerini (Workload Clusters)" sadece YAML dosyaları ile ayağa kaldırıp yönetebilir.

---

## 1. Neden Cluster API?

| Geleneksel Yöntem (IaC) | Cluster API (CAPI) Modeli |
|:---|:---|
| Terraform/Ansible ile kümeyi kur, state dosyasını sakla. | `kubectl apply -f cluster.yaml` ile küme oluştur. |
| Her bulut sağlayıcı için farklı betik ve araçlar (EKSCTL, AKS CLI). | Tek bir ortak API üzerinden tüm bulut sağlayıcıları yönet. |
| Küme sürümlerini (Kubernetes Upgrade) elle veya scriptlerle güncelle. | YAML dosyasında `version: v1.31.0` yaz, otomatik rolling upgrade başlasın. |
| Çöken bir node'u elle veya harici sunucu izleyicileriyle yeniden oluştur. | **MachineHealthCheck** ile otomatik arıza tespiti ve yeni node oluşturma. |

---

## 2. clusterctl Kurulumu ve Sağlayıcı Başlatma

CAPI yapılandırmalarını yönetmek için **clusterctl** CLI aracı kullanılır:

```bash
# 1. clusterctl CLI aracını indirin
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/latest/download/clusterctl-linux-amd64 -o clusterctl
chmod +x clusterctl
sudo mv clusterctl /usr/local/bin/

# 2. Yönetici kümeyi (Management Cluster) CAPI ile başlatın
# Local test için Docker sağlayıcısı (CAPD):
export CLUSTER_TOPOLOGY=true
clusterctl init --infrastructure docker

# AWS Sağlayıcısı (CAPA) için:
export AWS_REGION=eu-west-1
clusterctl init --infrastructure aws
```

---

## 3. Workload Cluster (İş Yükü Kümesi) Oluşturma

CAPI ile bir küme oluşturmak için şablon üretip bunu yönetici kümeye uygularız:

```bash
# Docker üzerinde 3 Control Plane ve 3 Worker node'a sahip bir küme şablonu üretin:
clusterctl generate cluster my-workload-cluster \
  --infrastructure docker \
  --kubernetes-version v1.30.0 \
  --control-plane-machine-count=3 \
  --worker-machine-count=3 > my-cluster.yaml

# Şablonu uygulayarak küme kurulumunu başlatın:
kubectl apply -f my-cluster.yaml
```

### Arka Planda Oluşan Kritik Kaynaklar

* `Cluster`: Kümenin temel tanımı ve ağ ayarları.
* `KubeadmControlPlane`: Control Plane düğümlerinin (master nodes) durumu ve versiyonu.
* `MachineDeployment`: Worker düğümlerinin ölçeklenme grubu (tıpkı Deployment gibi).

---

## 4. MachineHealthCheck (Otomatik Node Onarımı)

CAPI, bir sunucunun (Node) sağlıksız duruma düştüğünü (Örn: `NotReady` durumu) algıladığında, o sunucuyu otomatik olarak silip yerine yenisini ayağa kaldırmak için **MachineHealthCheck** kaynağını kullanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cluster_api_capi_manifest_1.yaml](../Manifests/11_multicluster/cluster_api_capi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. ClusterClass (Küme Şablonu Standardizasyonu)

Yüzlerce kümenin olduğu organizasyonlarda her küme için ayrı ayrı binlerce satır YAML yazmak yerine, platform ekipleri ortak bir **ClusterClass** tanımlar. Geliştiriciler ise sadece bu sınıfa referans vererek kümelerini hızlıca oluştururlar:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cluster_api_capi_manifest_2.yaml](../Manifests/11_multicluster/cluster_api_capi_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Küme Yönetimi ve Güncelleme (Rolling Upgrade)

Workload kümesini kurduktan sonra yönetmek için şu komutlar kullanılır:

```bash
# 1. Kümenin genel yapısını ve hazır olma durumunu CLI'dan izleyin
clusterctl describe cluster my-workload-cluster

# 2. İş yükü kümesine erişmek için kubeconfig dosyasını çekin:
clusterctl get kubeconfig my-workload-cluster > workload.kubeconfig
kubectl --kubeconfig=workload.kubeconfig get nodes

# 3. Worker sunucu sayısını anında 5'e yükseltin (Scale-out):
kubectl scale machinedeployment my-workload-cluster-workers --replicas=5

# 4. Kümenin Kubernetes Sürümünü Sıfır Kesintiyle Güncelleyin (Upgrade):
# Control Plane'i v1.31.0 yap:
kubectl patch kubeadmcontrolplane my-workload-cluster-control-plane \
  --type merge -p '{"spec":{"version":"v1.31.0"}}'
# Worker node'ları v1.31.0 yap:
kubectl patch machinedeployment my-workload-cluster-workers \
  --type merge -p '{"spec":{"template":{"spec":{"version":"v1.31.0"}}}}'
```

CAPI, master ve worker makineleri sırayla (rolling update mantığıyla) kapatıp yenilerini oluşturarak sürüm yükseltme işlemini sıfır kesintiyle tamamlar.
