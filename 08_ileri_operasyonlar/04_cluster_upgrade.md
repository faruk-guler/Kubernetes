# Kubernetes Cluster Upgrade

## 4.1 Upgrade Stratejisi

Kubernetes'te yalnızca **bir minor versiyon** ileri atlanabilir (örneğin v1.31→v1.32). İki versiyon atlamak desteklenmez.

```
v1.30 → v1.31 → v1.32 → v1.33   ✅ Desteklenir
v1.30 → v1.32                    âŒ Desteklenmez
```

## 4.2 kubeadm ile Upgrade

### Adım 1: Master Node Güncelleme

```bash
# Mevcut versiyon kontrolü
kubectl get nodes
kubeadm version

# kubeadm güncelle
apt-get update
apt-get install -y kubeadm=1.33.0-1.1

# Upgrade planını gör (ne değişecek?)
kubeadm upgrade plan

# Upgrade uygula
kubeadm upgrade apply v1.33.0

# kubelet ve kubectl güncelle
apt-get install -y kubelet=1.33.0-1.1 kubectl=1.33.0-1.1
systemctl daemon-reload
systemctl restart kubelet

# Doğrulama
kubectl get nodes
```

### Adım 2: Worker Node'ları Güncelleme (Teker Teker)

```bash
# Worker'ı drain et (pod'ları taşı)
kubectl drain k8s-worker-01 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

# Worker node'da:
apt-get update && apt-get install -y kubeadm=1.33.0-1.1
kubeadm upgrade node                  # Worker için bu komut
apt-get install -y kubelet=1.33.0-1.1 kubectl=1.33.0-1.1
systemctl daemon-reload && systemctl restart kubelet

# Master'dan worker'ı geri al
kubectl uncordon k8s-worker-01

# Sonraki worker'a geç
kubectl drain k8s-worker-02 ...
```

## 4.3 RKE2 ile Upgrade

```bash
# Server'ı güncelle
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.33.0+rke2r1 sh -
systemctl restart rke2-server

# Agent'ları güncelle (teker teker)
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_VERSION=v1.33.0+rke2r1 sh -
systemctl restart rke2-agent
```

## 4.4 Upgrade Öncesi Kontrol Listesi

```bash
# 1. etcd yedeği al
ETCDCTL_API=3 etcdctl snapshot save /backup/pre-upgrade-$(date +%Y%m%d).db ...

# 2. Tüm node'ların Ready durumunda olduğunu doğrula
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# 3. PodDisruptionBudget'ları kontrol et
kubectl get pdb -A

# 4. Deprecation kontrolü (eski API'lar)
kubectl deprecations  # Genellikle pluto aracıyla
```

## 4.5 Cilium Upgrade

```bash
# Cilium versiyon kontrolü
cilium version

# Upgrade planı
cilium upgrade --version 1.17.0 --dry-run

# Upgrade
cilium upgrade --version 1.17.0

# Doğrulama
cilium status --wait
cilium connectivity test
```

> [!TIP]
> **Pluto** aracı, upgrade öncesi deprecated API sürümlerini tespit eder:
> ```bash
> helm plugin install https://github.com/FairwindsOps/pluto
> kubectl pluto detect-helm -n production
> ```

---
