# kubespray

[Resmi Sitesi](https://github.com/kubernetes-sigs/kubespray)

Kubespray kubernetes kurulum ve bakımlarını otomatikle�Ytiren, ansible üzerine geli�Ytirilmi�Y, resmi bir araçtır.

Sa�Yladıkları:

* Otomasyon
* HA:  https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ha-mode.md
* node ekleme ve çıkarma, güncelleme
* Eklenti ekleme, çıkarma
* farklı kurulumları destekler 
    1. masterlar ve etcdler birlikte
    2. etcd serverlar ayrı sunucularda ( >=3, tek haneli)
    3. master ve etcd sayıları ayarlanabilir. 

## Kurulum

## Desktop Ortama Kurmak (Bonus)

Kendi ortamımızda test etmek istiyorsak [vagrant](vagrant.md) dosyasındaki vagrant ve virtualbox araçlarıyla hızlıca deneyebiliriz.

---



* Ansible kontrol makinası WSL ya da bir linux makinası olmak zorundadır. 
* Sunucular arasındaki eri�Yimler için [buraya](https://kubernetes.io/docs/reference/ports-and-protocols/) uyulmak zorundadır.

Kontrol makinasında pip3'ün kurulu olması gerekir.

### Do�Yrudan sistem üzerine ansible kurulumu

```bash

# redhat grubu
sudo dnf install python311
sudo alternatives --config python
sudo alternatives --config python3

# python virtual env
VENVDIR=kubespray-venv
KUBESPRAYDIR=${kubespray dizini}/
python3 -m venv $VENVDIR
source $VENVDIR/bin/activate
cd $KUBESPRAYDIR

# ``requirements.txt``ye göre gerekenleri kurun.
pip install -U -r requirements.txt

```

### kubespray hazır docker imajı kullanmak

```
# hangi sürüm kuracaksanız ona göre imaj seçilmesi gerekir. 
docker run --rm -it --mount type=bind,source="$(pwd)"/inventory/sample,dst=/inventory \
  quay.io/kubespray/kubespray:v2.29.0 bash
# Inside the container you may now run the kubespray playbooks:

ansible-playbook -i /inventory/inventory.ini cluster.yml [-b -kK -u $sudo_yetkili_user]

```


* ``inventory/sample`` hazır �Yablonunu ``inventory/mycluster`` olarak kopyala

```

cp -rfp inventory/sample inventory/mycluster

```

* Kubernetes kuraca�Yınız sunucuların listesini Ansible'a veriyoruz.
* Bu komut ip adreslerini ilk 2.si master ve etcd olacak �Yekilde nodelar olarak `inventory/mycluster/hosts.yaml` içerisine yazar. 

```

declare -a IPS=(<server1_ip> <server2_ip> <server3_ip>)
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

```

* ``inventory/mycluster/group_vars`` klasörü altındaki bu dosyaları gözden geçirin, de�Yi�Ytirmek istediklerinizi de�Yi�Ytirin. 

```
cat inventory/mycluster/group_vars/all/all.yml
cat inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

```

### ek ayarlar
* hostnameleri de�Yi�Ytirmek istemiyorsak

```
# inventory/mycluster/group_vars/all/all.yml dosyasının içine a�Ya�Yıdakini ekliyoruz.

override_system_hostname: false
```

* calico subnetlerini de�Yi�Ytirmek istiyorsak

```
# inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
# bu de�Yerleri uygun �Yekilde de�Yi�Ytiriyoruz. 
 76 kube_service_addresses: 10.233.0.0/18

 81 kube_pods_subnet: 10.233.64.0/18

# bunları ayarlayabilirsiniz. 

inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
auto_renew_certificates: true
auto_renew_certificates_systemd_calendar: "Sat *-*-1,2,3,4,5,6,7 03:{{ groups['kube_control_plane'].index(inventory_hostname) }}0:00"


```

* Ansible ile Kubespray'i çalı�Ytırın ve Kubernetes kümenizi kurun. Burada sudo yetkisine sahip bir kullanıcı gerekmektedir. E�Yer sunuculara parola ile eri�Yiyorsanız ``-kK`` size eri�Yim parolası ve sudo parolasını soracaktır.

[Güvenlik için güçlendirme](../09-G%C3%BCvenlik/kubespray-hardening.md)

```bash

# root kullanıcısı ile eri�Ymek için
ansible-playbook -i inventory/mycluster/hosts.yaml  --become --become-user=root cluster.yml

# sudo yetkisi olan bir kullanıcı ile eri�Ymek için
ansible-playbook -i inventory/mycluster/hosts.yaml -b cluster.yml -u <kullanıcı> -kK

# ek de�Yi�Ykenler ve hardening eklenmi�Y kurulum

ansible-playbook -v cluster.yml \
        -i inventory/mycluster/hosts.yaml \
        -become -u <kullanıcı> -kK \
        -e "@vars.yaml" \
        -e "@hardening.yaml"
```
*  Eksik bir �Yey yoksa yukarıdaki IPS tanımında verilen sunuculara kubernetes kümesi kurulacaktır. 

## Yeni nod ekleme

* worker node eklemek için. di�Yer tür nodlar için farklı süreçler vardır.
  
```
declare -a IPS=(<server1_ip> <server2_ip> <server3_ip> <yeni_nod_ip>)
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

ansible-playbook -i inventory/mycluster/hosts.yaml -b scale.yml -u <kullanıcı> -kK --limit=<host_yml_içindeki_node_name>

```

# autorenew seçilmemi�Yse sertifika yenileme

```
sudo /usr/local/bin/kubeadm certs check-expiration

# tüm master nodelarda a�Ya�Yıdaki komut çalı�Ytırılır
 
# tüm controller nodelarda bu çalı�Ytırılır.
sudo /usr/local/bin/k8s-certs-renew.sh
 
# tüm workerlarda kubelet restart edilir
 
sudo systemctl restart kubelet
```
## [Dashboard ve yeni eklenti kurma](dashboard.md)

* Kaynaklar
[Node Ekleme, De�Yi�Ytirme](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/operations/nodes.md)
