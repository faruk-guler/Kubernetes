# KubeVirt: Kubernetes Üzerinde Sanal Makineler

Modern altyapılarda klasik sanal makineler (Legacy Linux, Windows) ve konteynerler (Docker/Containerd) aynı "Control Plane" üzerinden, yani salt Kubernetes üzerinden yönetilir. Bunun 2026'daki standart aracı **KubeVirt**'tir.

---

## 7.1 KubeVirt Temel Kavramları

KubeVirt, Kubernetes ortamına "VirtualMachine" (VM) API nesnelerini entegre eder. Özünde her bir Sanal Makine, KVM ve QEMU tabanlı çalışan gizli bir Pod içerisinde çalıştırılır.

- **VirtualMachine (VM):** VM'nin kalıcı tanımı. Kapalı olsa bile yaşar.
- **VirtualMachineInstance (VMI):** Çalışmakta olan bir VM'yi temsil eder. Adeta Pod gibidir.
- **virtctl:** KubeVirt'e özel `kubectl` eklentisi.

---

## 7.2 Kurulum (Kısa Bakış)

```bash
# KubeVirt Operator'ının kurulması
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v1.1.0/kubevirt-operator.yaml

# KubeVirt Custom Resource (CR) ayağa kaldırılması
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v1.1.0/kubevirt-cr.yaml

# Durum kontrolü (Tüm bileşenler Running olmalıdır)
kubectl -n kubevirt get pods
```

---

## 7.3 Sanal Makine Tanımlama (YAML)

Kubernetes manifesti aracılığıyla 2 Çekirdek, 4GB RAM'e sahip bir Fedora sanal makine üretmek:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-fedora
spec:
  running: true             # Otomatik olarak VMI başlatılır
  template:
    metadata:
      labels:
        kubevirt.io/vm: vm-fedora
    spec:
      domain:
        resources:
          requests:
            memory: 4096M
        devices:
          disks:
          - name: containerdisk
            disk:
              bus: virtio
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/fedora-cloud-container-disk-demo:latest
```

---

## 7.4 VNC ve Konsol Erişimi (virtctl)

Sanal makinelerin ekranına (SSH dışında) VNC ile veya seri konsol ile erişmek gerektiğinde:

```bash
# virtctl CLI kurulumu (Krew ile)
kubectl krew install virt

# Seri konsola bağlanma
kubectl virt console vm-fedora

# VNC ara yüzüne bağlanma (Ekran kartı emülasyonu)
kubectl virt vnc vm-fedora

# VM'yi dışarıdan başlatma ve durdurma
kubectl virt start vm-fedora
kubectl virt stop vm-fedora
```

> [!NOTE]
> KubeVirt, konteynerize edilemeyen eski nesil Windows Server veya .NET Framework (Core olmayan) monolit bankacılık uygulamalarının on-premise bulut göçünde en güçlü araçtır. Data Plane'de Pod network'ü ve CNIsi (Cilium/Calico) VM'lere de aynı IP'leri atar, böylece VM'ler Pod'larla doğrudan konuşabilir.

---
*← [Ana Sayfa](../README.md)*
