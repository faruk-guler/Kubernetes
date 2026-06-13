# KubeVirt — Kubernetes Üzerinde Sanal Makine Yönetimi

KubeVirt, Kubernetes cluster'ında konteynerlerle birlikte sanal makineleri (VM) çalıştırmayı sağlayan CNCF Incubating projesidir. Containerize edilemeyen eski uygulamaları (Windows Server, .NET Framework, legacy Linux) Kubernetes'e taşımak için kullanılır.

---

## Ne Zaman Kullanılır?

```
✅ Containerize edilemeyen legacy uygulamalar
✅ Windows Server workload'ları
✅ Kernel erişimi gerektiren uygulamalar
✅ VM + container'ı aynı ağ ve platform üzerinde yönetmek
✅ Bare-metal'e geçiş sürecinde VMware/vSphere alternatifi
❌ Containerize edilebilen modern uygulamalar → pod kullan
```

---

## Kurulum

```bash
# KubeVirt Operator
export KUBEVIRT_VERSION=$(curl -sL https://api.github.com/repos/kubevirt/kubevirt/releases/latest | \
  grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

kubectl apply -f \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"

kubectl apply -f \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

# KVM emülasyon (cluster hardware virt desteklemiyorsa)
kubectl patch kubevirt kubevirt -n kubevirt \
  --type merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

# Kurulum doğrula
kubectl -n kubevirt wait kv kubevirt \
  --for condition=Available \
  --timeout=300s

kubectl get pods -n kubevirt
# NAME                               READY   STATUS
# virt-api-xxx                       1/1     Running
# virt-controller-xxx                1/1     Running
# virt-handler-xxx (her node)        1/1     Running

# virtctl CLI kurulumu
kubectl krew install virt
```

---

## VirtualMachine Tanımı

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ubuntu-server
  namespace: production
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: ubuntu-server
    spec:
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        memory:
          guest: 4Gi
        devices:
          disks:
          - name: rootdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}    # Pod ağına katıl
        resources:
          requests:
            memory: 4Gi
            cpu: "2"
          limits:
            memory: 4Gi
            cpu: "2"
      networks:
      - name: default
        pod: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: ubuntu-server-pvc
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: ubuntu
            password: changeme
            chpasswd: {expire: False}
            ssh_authorized_keys:
            - ssh-ed25519 AAAA... admin@company.com
---
# DataVolume — Ubuntu imajını PVC'ye indir
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ubuntu-server-pvc
  namespace: production
spec:
  source:
    registry:
      url: "docker://quay.io/containerdisks/ubuntu:22.04"
  storage:
    resources:
      requests:
        storage: 20Gi
    storageClassName: longhorn
```

---

## VM Yönetimi (virtctl)

```bash
# VM başlat / durdur / yeniden başlat
kubectl virt start ubuntu-server -n production
kubectl virt stop ubuntu-server -n production
kubectl virt restart ubuntu-server -n production

# Seri konsola bağlan
kubectl virt console ubuntu-server -n production

# VNC ile grafik ekrana bağlan
kubectl virt vnc ubuntu-server -n production

# VM içine SSH
kubectl virt ssh ubuntu@ubuntu-server -n production

# VM durumu
kubectl get vm -n production
kubectl get vmi -n production    # Çalışan instance

# Canlı göç (live migration) — VM'yi başka node'a taşı
kubectl virt migrate ubuntu-server -n production
kubectl get vmim -n production   # Migration durumu
```

---

## Live Migration

```yaml
# Live migration politikası
apiVersion: kubevirt.io/v1
kind: KubeVirt
metadata:
  name: kubevirt
  namespace: kubevirt
spec:
  configuration:
    migrations:
      parallelMigrationsPerCluster: 5
      parallelOutboundMigrationsPerNode: 2
      bandwidthPerMigration: 1Gi
      completionTimeoutPerGiB: 800
      progressTimeout: 150
```

```bash
# Node bakımı — VM'leri önce migrate et
kubectl virt drain <node-name> --delete-terminated-vmi

# Sonra node'u drain et
kubectl drain <node-name> --ignore-daemonsets
```

---

## VM'ye PVC Bağlama (Disk Ekle)

```yaml
# Mevcut VM'ye disk ekle (hot-plug)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-disk
  namespace: production
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: longhorn
```

```bash
# Çalışan VM'ye disk bağla
kubectl virt addvolume ubuntu-server \
  --volume-name=data-disk \
  --persist \
  -n production
```

---

## VM Ağ Yapısı

```
KubeVirt VM ağ modları:

masquerade (varsayılan):
  VM → Pod IP alır → cluster ağına katılır
  VM'ler Service ve NetworkPolicy ile yönetilir

bridge:
  VM doğrudan node ağına bağlanır
  VM'ye harici IP atanabilir (bare-metal için)

SR-IOV:
  VM'ye doğrudan NIC erişimi (yüksek performans)
```

```bash
# VM'ye bağlı Service oluştur
kubectl expose vm ubuntu-server \
  --port=22 \
  --target-port=22 \
  --type=ClusterIP \
  -n production
```

---

## Harvester — KubeVirt Tabanlı HCI

```
Harvester = KubeVirt + Longhorn + K3s
  → VMware vSphere'e açık kaynak alternatif
  → Bare-metal HCI (Hyper-Converged Infrastructure)
  → Web UI ile VM yönetimi
  → 2026'da SMB ve edge için yaygınlaşıyor
```

> [!TIP]
> KubeVirt, VM'leri pod gibi yönetir — aynı RBAC, NetworkPolicy, ResourceQuota kuralları geçerlidir. VM için ayrı bir orkestrasyon katmanı gerekmez.

> [!NOTE]
> KubeVirt production'da en iyi Longhorn (storage) + Multus (multi-network) + CDI (disk import) kombinasyonuyla kullanılır. Bu üç bileşen olmadan KubeVirt'in tam potansiyeline ulaşamazsınız.
