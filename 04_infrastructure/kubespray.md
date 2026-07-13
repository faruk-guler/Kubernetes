# Ansible ile Kubespray Kurulumu (Kubespray Guide)

**Kubespray**, Kubernetes topluluğu (SIG Cluster Lifecycle) tarafından desteklenen, Ansible playbook'ları üzerine kurulu, kurumsal seviyede yüksek kullanılabilirliğe (HA) sahip Kubernetes kümeleri kurmak ve yönetmek için kullanılan resmi ve son derece esnek bir araçtır.

Özellikle şirket içi (on-premise/bare-metal) veya AWS, GCP, OpenStack gibi platformlarda otomasyon odaklı ve tekrarlanabilir küme kurulumları için idealdir.

---

## 1. Neden Kubespray?

| Özellik | kubeadm | Kubespray |
|:---|:---|:---|
| **Yöntem** | Manuel CLI adımları | Ansible tabanlı tam otomasyon |
| **Ölçekleme** | Düğümlere tek tek bağlanarak yapılır | Ansible envanterini güncelleyerek tek komutla yapılır |
| **Eklentiler (Add-ons)** | Manuel yüklenir (Helm/YAML) | Kurulum aşamasında (Ingress, Monitoring vb.) otomatik kurulur |
| **Altyapı Bağımsızlığı**| Kısmi | Yüksek (Çoklu işletim sistemi ve bulut desteği) |
| **Ağ Kurulumu (CNI)** | Kubeadm sonrasında kurulur | Kurulum sırasında (Cilium, Calico, Flannel) otomatik yapılandırılır |

---

## 2. Kurulum Ön Gereksinimleri

Kubespray ile kurulum yapabilmek için iki temel bileşene ihtiyaç vardır:

1. **Ansible Kontrol Makinesi (Control Node):** Ansible komutlarını yürüteceğiniz makinedir. İşletim sistemi Linux veya Windows WSL olmak zorundadır (Ansible Windows üzerinde doğrudan çalışamaz).
2. **Kubernetes Hedef Sunucuları (Target Nodes):** Kubernetes kurulacak hedef düğümlerdir. Kontrol makinesinin bu sunuculara SSH anahtarı (SSH Key-based authentication) ve şifresiz `sudo` yetkisiyle erişebilmesi gerekir.

---

## 3. Kontrol Makinesinde Kurulum Adımları

Kubespray deposunu indirip bağımlılıkları yüklemek için Python sanal ortamı (virtual environment) kullanılması önerilir:

```bash
# 1. Kubespray deposunu klonlayın ve klasöre girin
git clone --depth 1 -b v2.29.0 https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# 2. Python sanal ortamı oluşturun ve aktif edin
python3 -m venv kubespray-venv
source kubespray-venv/bin/activate

# 3. Gerekli Ansible ve diğer Python bağımlılıklarını yükleyin
pip install -U -r requirements.txt
```

### Alternatif: Docker İmajı ile Kubespray Çalıştırma

Kontrol makinesine Python ve Ansible kurmak istemiyorsanız hazır Docker imajını kullanabilirsiniz:

```bash
docker run --rm -it --mount type=bind,source="$(pwd)"/inventory,dst=/inventory \
  quay.io/kubespray/kubespray:v2.29.0 bash

# Container içinden playbook çalıştırılabilir:
ansible-playbook -i /inventory/mycluster/hosts.yaml cluster.yml -b
```

---

## 4. Envanter (Inventory) ve Yapılandırma Hazırlığı

Kubespray envanter yapısını özelleştirmek için örnek şablonu kopyalayın:

```bash
# Örnek envanteri kopyalayın
cp -rfp inventory/sample inventory/mycluster

# Kurulacak sunucuların IP adreslerini bir dizi olarak tanımlayın
declare -a IPS=(192.168.10.10 192.168.10.11 192.168.10.12)

# Envanter oluşturucu scripti çalıştırarak hosts.yaml dosyasını otomatik üretin
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
```

Bu script, `inventory/mycluster/hosts.yaml` dosyasını ilk iki sunucu Master (ve etcd), son sunucu Worker olacak şekilde otomatik olarak yapılandırır.

---

## 5. Küme Yapılandırmasının Özelleştirilmesi

`inventory/mycluster/group_vars` altındaki yapılandırma dosyalarını açıp düzenleyebilirsiniz:

### 1. Sistem Hostname Değişimini Engelleme

Eğer sunucuların mevcut hostname değerlerinin değiştirilmesini istemiyorsanız `all/all.yml` dosyasına ekleyin:

```yaml
override_system_hostname: false
```

### 2. Pod ve Servis IP Bloklarını Belirleme

`k8s_cluster/k8s-cluster.yml` dosyasından ağ parametrelerini düzenleyebilirsiniz:

```yaml
kube_service_addresses: 10.233.0.0/18
kube_pods_subnet: 10.233.64.0/18
```

### 3. Sertifikaları Otomatik Yenileme

```yaml
auto_renew_certificates: true
```

---

## 6. Kurulum Playbook'unun Çalıştırılması

Ansible ile kuruluma hazırız. Kurulumu gerçekleştirmek için `cluster.yml` playbook'unu çalıştırın:

```bash
# 1. Doğrudan root kullanıcısı ile SSH erişimi varsa:
ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml

# 2. Sudo yetkili standart bir kullanıcı ile (Şifre sorarak -kK):
ansible-playbook -i inventory/mycluster/hosts.yaml -b cluster.yml -u yazilimci -kK

# 3. Kurulumu ek parametre ve güvenlik sıkılaştırmalarıyla (Hardening) tetikleme:
ansible-playbook -v cluster.yml \
  -i inventory/mycluster/hosts.yaml \
  --become -u yazilimci -kK \
  -e "@vars.yaml" \
  -e "@hardening.yaml"
```

---

## 7. Düğüm Ekleme ve Ölçekleme (Scaling Nodes)

Mevcut bir kümeye yeni bir Worker düğümü eklemek için hosts.yaml envanter dosyanıza yeni IP'yi ekleyin ve `scale.yml` playbook'unu çalıştırın:

```bash
# Envanter dosyasını yeni sunucuyla güncelleyin
declare -a IPS=(192.168.10.10 192.168.10.11 192.168.10.12 192.168.10.13)
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

# Sadece yeni eklenen sunucuyu yapılandırmak için --limit belirterek çalıştırın
ansible-playbook -i inventory/mycluster/hosts.yaml -b scale.yml -u yazilimci -kK --limit=node4
```

---

## 8. Manuel Sertifika Yenileme

Eğer otomatik sertifika yenileme aktif edilmediyse, sertifikaların süresi dolmadan önce el ile yenileme işlemi şu şekilde Ansible üzerinden veya yerel scriptlerle yapılabilir:

```bash
# Tüm master düğümlerinde yenileme scriptini tetikleme
sudo /usr/local/bin/k8s-certs-renew.sh

# Değişikliklerin yansıması için tüm worker düğümlerinde kubelet'i yeniden başlatma
sudo systemctl restart kubelet
```

---

## Özet

Kubespray, kurumsal veri merkezlerinde (on-premise) Kubernetes altyapısını kod olarak yönetmek (**Infrastructure as Code**) için eşsiz bir araçtır. Kurulum aşamasından güncellemeye (`upgrade.yml`), ölçeklemeden (`scale.yml`) kaldırmaya (`reset.yml`) kadar tüm küme yaşam döngüsünü tek bir Ansible kontrol merkezinden yönetmenize imkan tanır.
