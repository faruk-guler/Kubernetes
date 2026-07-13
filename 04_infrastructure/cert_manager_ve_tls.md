# Kubernetes Ekosistemi ve Yardımcı Araçlar

Kubernetes kendi başına bir orkestrasyon motorudur; ancak gerçek dünyada üretim (production) ortamında tam teşekküllü bir altyapı sunmak için ekosistemdeki diğer açık kaynaklı araçlarla desteklenmesi gerekir.
Bu bölümde, bare-metal veri merkezlerinden bulut entegrasyonlarına kadar en popüler ve kritik Kubernetes yardımcı araçlarını, yönetim arayüzlerini ve Kubernetes'i sanal makinelere genişleten teknolojileri inceleyeceğiz.

---

## 1. Çoklu Küme Yönetimi: Rancher

Şirketinizde onlarca Kubernetes kümesi (EKS, AKS, bare-metal, edge) olduğunda, her birine ayrı ayrı `kubeconfig` ile bağlanıp yönetmek güvenlik ve yönetim kaosu yaratır. **Rancher**, tüm kümelerinizi tek bir web arayüzünden (GUI) yönetmenizi sağlayan merkezi bir platformdur.

* **Merkezi Kimlik Doğrulama (Auth):** Active Directory, LDAP veya Okta entegrasyonu ile tüm kümelere tek bir yerden erişim yetkisi (RBAC) tanımlayabilirsiniz.
* **Multi-Cluster Kataloğu:** Uygulamaları tek tıkla tüm kümelere dağıtabilirsiniz.
* **Güvenlik Politikaları:** Kümeler genelinde CIS güvenlik taramaları çalıştırabilir ve merkezi ağ politikaları uygulayabilirsiniz.

---

## 2. Bare-Metal Ağ Çözümü: MetalLB ve ExternalDNS

Bulut sağlayıcılarda (AWS, GCP) `Type: LoadBalancer` tipinde bir servis oluşturduğunuzda, arka planda otomatik olarak AWS ELB gibi bir yük dengeleyici açılır ve size dışarıdan erişilebilir bir IP verir. Ancak kendi fiziksel sunucularınızda (bare-metal) bu işlemi yaptığınızda servis **Pending** durumunda takılı kalır; çünkü fiziksel veri merkezinizde bu IP'yi atayacak bir bulut kontrolörü yoktur.

### MetalLB

Bare-metal Kubernetes kümelerinde LoadBalancer hizmeti sunan bir ağ kontrolörüdür.

* **Çalışma Modları:**
  * **L2 Modu (Layer 2):** Sunuculardan birini "lider" seçer ve ARP/NDP protokolleriyle IP adresini o sunucuya yönlendirir. Kurulumu çok basittir ancak tek bir sunucu darboğaz (bottleneck) yaratabilir.
  * **BGP Modu:** Kümenizdeki sunucuları doğrudan veri merkezinizin fiziksel yönlendiricilerine (Router) BGP komşusu olarak bağlar. Gerçek bir yük dengeleme ve yüksek kullanılabilirlik sunar.

**MetalLB IP Havuzu Tanımı (IPAddressPool):**

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cert_manager_ve_tls_manifest_1.yaml](../Manifests/04_infrastructure/cert_manager_ve_tls_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### ExternalDNS

Kubernetes üzerindeki Ingress veya Service kaynaklarını dinleyerek, dış dünyadaki DNS sunucularında (Cloudflare, AWS Route53, Google Cloud DNS vb.) otomatik olarak DNS kaydı (A veya CNAME) oluşturan bir araçtır.

* **Faydası:** Bir Ingress oluşturduğunuzda `api.company.com` adresini DNS sağlayıcınıza elle girmek zorunda kalmazsınız; ExternalDNS bunu saniyeler içinde API üzerinden kaydeder.

---

## 3. Depolama Operatörü: Rook (Ceph)

Kendi sunucularınızda (On-Premise) AWS EBS benzeri dinamik, ölçeklenebilir ve yüksek kullanılabilirliğe sahip block/file storage ihtiyacını karşılamak için **Rook** kullanılır.
Rook, açık kaynaklı dağıtık depolama sistemi olan **Ceph**'i bir Kubernetes Operatörüne dönüştürür.

* **Nasıl Çalışır?** Sunucularınızdaki boş hard diskleri (SSD/NVMe) algılar, bunları tek bir ortak havuzda birleştirir ve Kubernetes podlarına dinamik PersistentVolume (PV) olarak sunar.
* **Self-Healing:** Disklerden biri yandığında Ceph, veriyi diğer disklerden otomatik olarak çoğaltarak veri kaybını engeller.

---

## 4. Kubernetes Üzerinde Sanal Makine: KubeVirt

Şirketinizde hala konteynerleştirilememiş, eski işletim sistemi bağımlılığı olan (Legacy) sanal makineler (VM) olabilir. Bunları yönetmek için ayrı bir VMware/Proxmox altyapısı, konteynerler için ayrı bir Kubernetes altyapısı tutmak operasyonel yük oluşturur.

**KubeVirt**, Kubernetes'in sanal makineleri de yerel birer nesne (Custom Resource) olarak yönetmesini sağlar.

* **Mantığı:** Bir sanal makine, Kubernetes kümesinde standart bir podun içinde çalıştırılır. VM diskleri PVC olarak bağlanır, ağ trafiği ise Kubernetes servisleri üzerinden yönlendirilir.
* Geliştiriciler tek bir YAML ile hem podları hem de sanal makineleri aynı kümede, aynı ağ politikasında ve aynı izleme araçlarıyla yönetebilirler.

---

## 5. TLS ve Sertifika Yönetimi: Cert-Manager

Canlı ortamlarda HTTP trafiğinin mutlaka HTTPS (SSL/TLS) ile şifrelenmesi gerekir. **Cert-Manager**, Kubernetes kümelerinde sertifika yönetimini otomatize eden en popüler araçtır.

* **Otomatik Yenileme:** Let's Encrypt, HashiCorp Vault veya kendi iç CA sisteminizle konuşarak sertifikaları otomatik üretir ve süreleri dolmadan (genellikle 90 gün) otomatik yeniler.
* Ingress tanımlarınıza sadece tek bir annotation (etiket) ekleyerek sertifika sürecini tamamen otomatize edebilirsiniz.

---

## 6. Kubernetes Yönetim Arayüzleri: Lens ve OpenLens

Komut satırı (`kubectl`) çok güçlü olsa da, tüm kümeyi görselleştirmek, hızlıca log incelemek ve kaynak tüketimini anlık grafiklerle görmek için bir masaüstü arayüzü (IDE) kullanmak işleri hızlandırır.

* **Lens (veya Açık Kaynaklı alternatifi OpenLens):** 2026 yılının en popüler Kubernetes masaüstü tarayıcısıdır.
* **Özellikleri:**
  * Kümeye ait tüm podları, servisleri, diskleri tek bir tıklamayla görüntüleme.
  * Podların içine tek tıkla terminal (exec) açma veya logları canlı akışla izleme.
  * Helm chart'larını doğrudan arayüzden arayıp kurabilme ve güncelleme.
  * CPU/RAM metriklerini anlık grafiklerle sunma.

---

## 7. Özet

Kubernetes ekosistemi, orkestrasyonun sınırlarını aşarak veri merkezinizin tüm bileşenlerini (Ağ, Depolama, Güvenlik, Sanallaştırma) tek bir kontrol düzlemi (Control Plane) altında birleştirmemizi sağlar.
Modern altyapı yönetiminde bu araçların entegrasyonu, operasyonel yükü azaltmanın ve gerçek anlamda bulut-yerel (cloud-native) olmanın tek yoludur.
