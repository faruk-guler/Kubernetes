# Cluster API (CAPI)

Cluster API, Kubernetes cluster'larının yaşam döngüsünü — oluşturma, yükseltme, silme — Kubernetes'in kendi bildirimsel modeli ile yönetir. "Kubernetes ile Kubernetes yönetmek" prensibidir.

---

## Neden Cluster API?

| Geleneksel | CAPI |
|:-----------|:-----|
| Terraform ile cluster kur | YAML apply → Cluster oluşur |
| Her provider için farklı araç | Tek API, çoklu provider |
| Cluster upgrade elle | YAML patch → otomatik rolling upgrade |
| Arızalı node'u elle değiştir | MachineHealthCheck → otomatik |

**Provider'lar:** `CAPD` (Docker/lab), `CAPA` (AWS), `CAPZ` (Azure), `CAPG` (GCP), `CAPV` (vSphere), `CAPM3` (Bare-metal)

---

## Kurulum

```bash
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/latest/download/clusterctl-linux-amd64 \
  -o clusterctl && chmod +x clusterctl && mv clusterctl /usr/local/bin/

# Docker provider (lab)
export CLUSTER_TOPOLOGY=true
clusterctl init --infrastructure docker

# AWS provider
export AWS_REGION=eu-west-1
clusterctl init --infrastructure aws
```

---

## Cluster Oluşturma

```bash
clusterctl generate cluster my-cluster \
  --infrastructure docker \
  --kubernetes-version v1.30.0 \
  --control-plane-machine-count=3 \
  --worker-machine-count=3 > my-cluster.yaml

kubectl apply -f my-cluster.yaml
```

```yaml
# Temel objeler
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
  controlPlaneRef:
    kind: KubeadmControlPlane
    name: my-cluster-control-plane
  infrastructureRef:
    kind: DockerCluster
    name: my-cluster
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: my-cluster-workers
spec:
  clusterName: my-cluster
  replicas: 3
  template:
    spec:
      version: v1.30.0
```

---

## Cluster Yönetimi

```bash
# Durum izle
clusterctl describe cluster my-cluster

# Kubeconfig al
clusterctl get kubeconfig my-cluster > workload.kubeconfig
kubectl --kubeconfig=workload.kubeconfig get nodes

# Scale out
kubectl scale machinedeployment my-cluster-workers --replicas=5

# Kubernetes upgrade (rolling)
kubectl patch kubeadmcontrolplane my-cluster-control-plane \
  --type merge -p '{"spec":{"version":"v1.31.0"}}'

kubectl patch machinedeployment my-cluster-workers \
  --type merge -p '{"spec":{"template":{"spec":{"version":"v1.31.0"}}}}'
```

---

## MachineHealthCheck (Otomatik Onarım)

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineHealthCheck
metadata:
  name: worker-health
spec:
  clusterName: my-cluster
  selector:
    matchLabels:
      cluster.x-k8s.io/deployment-name: my-cluster-workers
  unhealthyConditions:
  - type: Ready
    status: "False"
    timeout: 300s    # 5 dakika NotReady → makineyi değiştir
  maxUnhealthy: 33%  # Aynı anda en fazla %33 değiştirilir
```

---

## ClusterClass (Şablon Yönetimi)

```yaml
# Standart cluster şablonu tanımla
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: production-class
spec:
  controlPlane:
    ref:
      kind: KubeadmControlPlaneTemplate
      name: prod-cp-template
  workers:
    machineDeployments:
    - class: default-worker
      template:
        infrastructure:
          ref:
            kind: DockerMachineTemplate
            name: prod-worker
```

```yaml
# Şablondan cluster türet
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: team-alpha-cluster
spec:
  topology:
    class: production-class
    version: v1.30.0
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
      - name: default-worker
        replicas: 5
```

---

## İzleme ve Temizlik

```bash
# Tüm CAPI objeleri
kubectl get clusters,machines,machinedeployments -A

# Cluster hazır mı?
kubectl get cluster my-cluster \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Cluster sil
kubectl delete cluster my-cluster
```
