# Windows Containers on Kubernetes

Kubernetes, Linux workload'larının yanı sıra **Windows Server node'larını** da destekler. Bu özellik özellikle .NET Framework uygulamalarını containerize etmek ve Kubernetes'e taşımak için kritiktir.

---

## Windows Node Desteği — Genel Bakış

```
Linux Node:    Linux container'ları çalıştırır (varsayılan)
Windows Node:  Windows Server container'ları çalıştırır

Önemli:  Control plane (API Server, etcd, scheduler) HER ZAMAN Linux'ta çalışır
         Sadece worker node'lar Windows olabilir
```

**Desteklenen Windows versiyonları:**
- Windows Server 2019 (LTSC)
- Windows Server 2022 (LTSC) — önerilen

---

## Node Kurulumu

```powershell
# Windows Server 2022 node kurulumu (containerd)
# Containerd kurulumu
winget install ContainerD.containerd

# CNI plugin (Calico veya Flannel — her ikisi Windows destekler)
# Calico Windows için:
Invoke-WebRequest -Uri https://projectcalico.docs.tigera.io/scripts/install-calico-windows.ps1 | Select-Object -ExpandProperty Content | powershell

# Kubernetes node join
kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### Cloud Provider'larda Windows Node Pool

```bash
# AKS — Windows node pool
az aks nodepool add \
  --resource-group myRG \
  --cluster-name myAKS \
  --name winnp \
  --node-count 2 \
  --os-type Windows \
  --node-vm-size Standard_D4s_v3 \
  --os-sku Windows2022

# EKS — Windows managed node group
eksctl create nodegroup \
  --cluster my-cluster \
  --name windows-ng \
  --node-type m5.xlarge \
  --nodes 2 \
  --ami-family WindowsServer2022CoreContainer

# GKE — Windows node pool
gcloud container node-pools create windows-pool \
  --cluster=my-cluster \
  --image-type=WINDOWS_LTSC_CONTAINERD \
  --machine-type=n2-standard-4 \
  --num-nodes=2
```

---

## Windows Pod Manifest

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dotnet-app
  namespace: production
spec:
  nodeSelector:
    kubernetes.io/os: windows     # Windows node'a yönlendir

  tolerations:
  - key: "os"
    operator: "Equal"
    value: "windows"
    effect: "NoSchedule"

  containers:
  - name: dotnet-app
    image: mcr.microsoft.com/dotnet/aspnet:8.0-nanoserver-ltsc2022
    ports:
    - containerPort: 8080
    env:
    - name: ASPNETCORE_URLS
      value: "http://+:8080"
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
      limits:
        cpu: "2"
        memory: "2Gi"

---
# Windows Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iis-server
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: iis
  template:
    metadata:
      labels:
        app: iis
    spec:
      nodeSelector:
        kubernetes.io/os: windows
      tolerations:
      - key: "os"
        operator: "Equal"
        value: "windows"
        effect: "NoSchedule"
      containers:
      - name: iis
        image: mcr.microsoft.com/windows/servercore/iis:windowsservercore-ltsc2022
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30    # Windows container başlatma yavaştır
          periodSeconds: 10
```

---

## Taint & Toleration Stratejisi

Windows node'ların Linux pod çalıştırmasını engellemek için:

```bash
# Windows node'lara taint ekle
kubectl taint nodes <windows-node> os=windows:NoSchedule

# Tüm Windows node'lara toplu taint
kubectl get nodes -l kubernetes.io/os=windows \
  -o name | xargs -I{} kubectl taint {} os=windows:NoSchedule
```

Linux pod'ları Windows node'a atanmasını engellemek için node affinity:

```yaml
# Linux pod spec'ine ekle (varsayılan olarak Linux çalışır ama açık belirtmek iyi pratik)
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values:
            - linux
```

---

## Windows Container Image'ları

```dockerfile
# .NET 8 WebAPI — Windows Nano Server
FROM mcr.microsoft.com/dotnet/sdk:8.0-nanoserver-ltsc2022 AS build
WORKDIR /app
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /out

FROM mcr.microsoft.com/dotnet/aspnet:8.0-nanoserver-ltsc2022 AS runtime
WORKDIR /app
COPY --from=build /out .
EXPOSE 8080
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

**Microsoft resmi base image'lar:**

| Image | Boyut | Kullanım |
|:------|------:|:---------|
| `windows/nanoserver:ltsc2022` | ~100 MB | .NET, minimal uygulamalar |
| `windows/servercore:ltsc2022` | ~3.5 GB | IIS, COM, MSI gerektiren uygulamalar |
| `dotnet/aspnet:8.0-nanoserver-ltsc2022` | ~150 MB | ASP.NET Core |
| `dotnet/runtime:8.0-nanoserver-ltsc2022` | ~130 MB | Console .NET uygulamaları |

> [!WARNING]
> **Image uyumluluğu kritik:** Windows container, çalıştığı Windows host versiyonuyla uyumlu olmalıdır. ltsc2022 image → Windows Server 2022 node gerektirir. Hata: "The container operating system does not match the host operating system."

---

## Linux/Windows Aynı Cluster — Karma Deployment

```yaml
# Hem Linux hem Windows pod'u olan DaemonSet
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux       # Sadece Linux node'lar
      containers:
      - name: log-collector
        image: fluent/fluent-bit:3.2
```

---

## Windows'a Özgü Kısıtlamalar

| Özellik | Linux | Windows |
|:--------|:-----:|:-------:|
| HostNetwork | ✅ | ❌ |
| HostPID | ✅ | ❌ |
| Privileged containers | ✅ | ❌ |
| Init containers | ✅ | ✅ (K8s 1.29+) |
| CSI storage | ✅ | Kısıtlı |
| GPU support | ✅ | ✅ (DirectX API) |
| eBPF | ✅ | ❌ |
| Rootless containers | ✅ | ❌ |

> [!NOTE]
> Windows container'lar Linux alternatiflerinden genellikle 3-5x daha fazla bellek kullanır. .NET 8+ uygulamalarını mümkünse Linux'a taşımak (Docker Linux image ile) hem maliyet hem performans açısından avantajlıdır.
