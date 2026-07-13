# Çoklu Kiracılık (Multi-Tenancy) ve Crossplane

Kurumsal seviyedeki Kubernetes yönetiminin en önemli hedeflerinden biri, tek bir altyapıyı birden fazla bağımsız ekibe veya müşteriye (tenant) güvenli, izole ve verimli bir şekilde sunabilmektir.
Bu bölümde, çoklu kiracılık (Multi-Tenancy) modellerini, hiyerarşik namespace yapılarını (HNC), sanal kümeleri (vCluster) ve Kubernetes'i bulut kaynaklarını yöneten bir kontrol merkezine dönüştüren **Crossplane** teknolojisini inceleyeceğiz.

---

## 1. Çoklu Kiracılık Modelleri: Soft vs. Hard Tenancy

Aynı donanımı paylaşan kiracılar arasındaki izolasyon seviyesine göre iki temel yaklaşım vardır:

* **Soft Multi-Tenancy (Namespace Bazlı):** Ekipler aynı Kubernetes kümesini ve aynı Control Plane beynini paylaşır. Güvenlik; Namespace, RBAC yetkilendirmesi, NetworkPolicy (Ağ kısıtlama) ve ResourceQuota (Kaynak sınırları) ile sağlanır. İç ekipler (Güvenilir kiracılar) için idealdir.
* **Hard Multi-Tenancy (Küme Bazlı):** Kiracılar birbirine güvenmez (Örn: SaaS müşterileri). Her kiracıya tamamen izole fiziksel bir küme veya sanal bir küme (vCluster) atanır. Güvenlik en üst seviyededir ancak maliyet yüksektir.

---

## 2. Hiyerarşik Namespace Kontrolörü (HNC)

Büyük organizasyonlarda ekiplerin hiyerarşik yapıları vardır. Örneğin, `team-alpha` adında bir ana departmanın altında `team-alpha-dev` ve `team-alpha-prod` alt ekipleri bulunur.
**HNC (Hierarchical Namespace Controller)**, namespace'ler arasında ebeveyn-çocuk ilişkisi kurarak yönetim kolaylığı sağlar.

### HNC Kurulumu

```bash
kubectl apply -f https://github.com/kubernetes-sigs/hierarchical-namespaces/releases/latest/download/default.yaml
```

### Hiyerarşik Yapı Oluşturma (kubectl hns)

```bash
# Alt namespace oluştur
kubectl hns create team-alpha-dev -n team-alpha
kubectl hns create team-alpha-prod -n team-alpha

# Hiyerarşi ağacını görüntüle
kubectl hns tree team-alpha
# team-alpha
# ├── team-alpha-dev
# └── team-alpha-prod
```

* **Faydası:** Ebeveyn namespace olan `team-alpha` üzerinde tanımladığınız bir RBAC rolü veya NetworkPolicy, alt namespace'lere otomatik olarak miras aktarılır (propagate). Her alt klasör için tek tek yetki yazmak zorunda kalmazsınız.

---

## 3. Sanal Kümeler: vCluster

**vCluster (Virtual Cluster)**, fiziksel bir Kubernetes kümesinin içine kurulmuş, tamamen bağımsız ve sanal bir Kubernetes kümesidir. Tıpkı fiziksel bir bilgisayarın içinde sanal makine (VM) açmaya benzer.

* Geliştiriciler bu sanal kümeye bağlandıklarında kendilerini **Cluster Admin** (en yetkili kullanıcı) olarak görürler, CRD oluşturabilirler. Ancak arka planda, fiziksel kümenin sadece kendilerine ayrılmış bir namespace'i içinde (birer pod olarak) çalışırlar.

### vCluster Oluşturma ve Bağlanma

```bash
# 1. Sanal küme oluştur
vcluster create tenant-company-a -n vcluster-company-a --create-namespace

# 2. Bağlantı kubeconfig dosyasını dışarı aktar
vcluster connect tenant-company-a -n vcluster-company-a > tenant-a.kubeconfig

# 3. Sanal kümeyi yönetin (Sanal admin yetkisiyle)
kubectl --kubeconfig=tenant-a.kubeconfig get nodes
```

---

## 4. Altyapı Yönetimi: Crossplane (IaC on K8s)

Geleneksel Infrastructure as Code (IaC) araçları (Terraform gibi) bulut kaynaklarını başarıyla kurar. Ancak en büyük sorunları **Config Drift** (Bir uzmanın AWS panelinden elle kaynağı değiştirmesiyle kodun gerçeği yansıtmaması) durumudur.

**Crossplane**, Kubernetes'in sonsuz uzlaşma döngüsünü (Reconciliation Loop) kullanarak bulut kaynaklarını yönetir. Terraform gibi çalıştır-bırak yapmaz; AWS/GCP kaynaklarını saniyede onlarca kez kontrol ederek kodun dışına çıkılmasını (drift) engeller.

```
Git Repo (YAML) ──► ArgoCD ──► Kubernetes API ──► Crossplane ──► AWS/Azure/GCP
                                   ▲                │
                                   └── Reconcile ───┘
```

### AWS S3 Bucket Oluşturma Örneği

Crossplane kurulduktan sonra AWS Provider tanımlanır ve doğrudan Kubernetes YAML'ı ile AWS üzerinde bir S3 depolama alanı açılabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [coklu_kiracilik_kaliplari_manifest_1.yaml](../Manifests/03_architecture/coklu_kiracilik_kaliplari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

```bash
# Kaynağı sorgulayın (Crossplane AWS'de oluşturduğunda READY=True olacaktır)
kubectl get bucket company-app-assets-production
# NAME                            READY   SYNCED   AGE
# company-app-assets-production   True    True     45s
```

### Composite Resource (XRD) ile Self-Servis Platform (PaaS)

Platform ekibi, karmaşık AWS parametrelerini gizleyerek yazılımcılar için basit bir şablon (Custom Resource) tanımlar. Yazılımcı sadece `XDatabase` adında bir nesne talep eder. Crossplane arka planda AWS üzerinde VPC, Subnet, RDS Instance, Güvenlik Duvarı kurallarını otomatik yapılandırarak yazılımcıya sadece bağlantı şifresini (Secret) iade eder.

---

## 5. Özet

Çoklu kiracılık (Multi-Tenancy) yapıları, şirket içi kaynakların adil ve güvenli kullanılmasını sağlar. **Crossplane** ise altyapı ekiplerinin bulut kaynaklarını Kubernetes API'si arkasına gizleyerek geliştiricilere tamamen self-servis, standartlaştırılmış bir "Platform as a Service (PaaS)" sunabilmesinin kapılarını aralar.
