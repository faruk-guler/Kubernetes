# KubeVirt ile Kubernetes Üzerinde Sanal Makine Yönetimi

Geleneksel kurumsal altyapılarda sanal makineler (VMware, Proxmox, Hyper-V) ile konteynerler (Kubernetes) yıllarca iki ayrı siloda yönetildi. Ancak VMware lisanslama modellerindeki köklü değişimler ve altyapı sadeleştirme hedefleri, sanal makineleri doğrudan Kubernetes kontrol düzlemi altına taşımayı zorunlu hale getirdi.

**KubeVirt**, Kubernetes'i tam yetenekli bir sanallaştırma hipervizör orkestratörüne dönüştüren CNCF projesidir. KubeVirt sayesinde sanal makineler, Kubernetes içinde yerel nesneler (`VirtualMachine` ve `VirtualMachineInstance`) olarak podlarla yan yana çalışır, aynı ağı ve aynı depolama sınıflarını paylaşır.

---

## 1. Mimari ve Bileşenler

KubeVirt, Kubernetes kontrol düzlemini yerel Linux KVM (Kernel-based Virtual Machine) çekirdek teknolojisiyle buluşturur:

```text
┌────────────────────────────────────────────────────────┐
│                   Kubernetes API                       │
└───────────┬────────────────────────────────┬───────────┘
            │                                │
            ▼                                ▼
     ┌──────────────┐                 ┌──────────────┐
     │   virt-api   │                 │ virt-control │
     └──────┬───────┘                 └──────┬───────┘
            │                                │
            └────────────────┬───────────────┘
                             ▼
┌────────────────────────────────────────────────────────┐
│ Düğüm (Node):                                          │
│  ┌──────────────┐   ┌────────────────────────────────┐ │
│  │ virt-handler │──►│ Pod: virt-launcher             │ │
│  │ (DaemonSet)  │   │   └─► libvirt + QEMU/KVM (VM)  │ │
│  └──────────────┘   └────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

* **`virt-api`:** Sanal makinelere özgü API isteklerini karşılayan ve CRD doğrulamasını yapan giriş kapısıdır.
* **`virt-controller`:** VM'lerin yaşam döngüsünü, düğümlere atanmasını ve durum senkronizasyonunu denetler.
* **`virt-handler`:** Her işçi düğümde `DaemonSet` olarak çalışır. Yerel KVM aygıtı (`/dev/kvm`) ile doğrudan konuşarak sanal makinelerin başlatılmasını tetikler.
* **`virt-launcher`:** Sanal makinenin içinde çalıştığı Kubernetes Pod'udur. Her VM için bir `virt-launcher` podu açılır ve QEMU/libvirt süreçlerini sarmalar.

---

## 2. Örnek Sanal Makine Tanımı (`VirtualMachine`)

Aşağıda 2 vCPU, 4GiB bellek ve Cloud-Init başlatma betiğine sahip yalın bir `VirtualMachine` manifestosu yer almaktadır:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ubuntu-vm
spec:
  running: true # true yapıldığında VM otomatik başlatılır
  template:
    spec:
      domain:
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
        resources:
          requests:
            memory: 2Gi
            cpu: "1"
      volumes:
        - name: rootdisk
          dataVolume:
            name: ubuntu-boot-dv
```

---

## 3. VM Disk Yönetimi: CDI ve DataVolume

Sanal makinelerin açılabilmesi için disk imajlarına (ISO, QCOW2, RAW) ihtiyaç duyulur. Bu süreci otomatikleştirmek için **Containerized Data Importer (CDI)** kullanılır.

CDI, standart PVC nesnesini **`DataVolume` (DV)** adında üst seviye bir kaynakla sarmalar:

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ubuntu-boot-dv
  namespace: workloads
spec:
  source:
    http:
      url: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
    storageClassName: local-nvme-sc
```

* CDI denetleyicisi imajı webden indirir, QCOW2 formatından çıkartıp PVC'ye yazar ve VM'in boot etmesi için hazır hale getirir.

---

## 4. Sanal Makine Ağ Modelleri

KubeVirt sanal makinelerine ağ bağlantısı üç farklı yöntemle sağlanır:

1. **Masquerade (Varsayılan):** VM trafiğini pod ağı arkasında NAT (Network Address Translation) ile gizler. Standart Kubernetes `Service` (ClusterIP, NodePort) veya Ingress nesneleriyle dış dünyaya açmak için en uygun modeldir.
2. **Bridge (Köprü):** VM'i doğrudan pod ağına bağlar; VM kendi L2 MAC adresini duyurur.
3. **Multus CNI Entegrasyonu:** VM'e pod ağından tamamen bağımsız, veri merkezindeki fiziksel VLAN veya Switch portundan doğrudan IP alabilmesi için ikinci/üçüncü bir ağ arabirimi ekler.

---

## 5. Komut Satırı Aracı: `virtctl`

Kubernetes podlarından farklı olarak, bir sanal makinenin BIOS/EFI ekranını izlemek, VNC konsoluna bağlanmak veya anlık ekran görüntüsü almak için `virtctl` komut satırı aracı kullanılır:

```bash
# VM'i başlatma ve durdurma
virtctl start ubuntu-workload-vm -n workloads
virtctl stop ubuntu-workload-vm -n workloads

# VM seri konsoluna (TTY) bağlanma
virtctl console ubuntu-workload-vm -n workloads

# Grafiksel masaüstü (VNC) oturumu açma
virtctl vnc ubuntu-workload-vm -n workloads

# Çalışan VM'i başka bir düğüme canlı taşıma (Live Migration)
virtctl migrate ubuntu-workload-vm -n workloads
```

---

## 6. Canlı Taşıma (Live Migration)

Düğümlerden birinde donanım arızası veya bakım planlandığında, üzerinde koşan sanal makineyi kapatmadan (zero downtime) başka bir Kubernetes düğümüne taşımak mümkündür:

* **Gereksinim:** VM diskinin `ReadWriteMany` (RWX) destekleyen paylaşımlı bir depolama biriminde (Ceph, NFS, SAN) bulunması gerekir.
* `virt-controller`, hedef düğümde yeni bir `virt-launcher` podu açar, bellek içeriğini ağ üzerinden aktarır ve mikro-saniyelik bir duraklama ile trafiği yeni düğüme yönlendirir.

---

## Özet

KubeVirt, konteynerleştirilmesi maliyetli veya imkansız olan eski (legacy) sanal makineleri modern Kubernetes ekosistemine entegre eder. Geliştiriciler ve sistem yöneticileri; podları, mikoservisleri ve sanal makineleri tek bir GitOps boru hattı ve tek bir izleme paneli (Prometheus/Grafana) üzerinden yönetebilir.
