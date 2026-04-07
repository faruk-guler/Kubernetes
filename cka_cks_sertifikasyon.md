# 🎓 CKA / CKS Sertifikasyon Hazırlık Rehberi

Bu bölüm, Certified Kubernetes Administrator (CKA) ve Certified Kubernetes Security Specialist (CKS) sınavlarına hazırlık için derlenmiş pratik notlar, zamanlama stratejileri ve lab çalışmalarını içerir.

## Sınav Genel Bilgileri

| Özellik | CKA | CKS |
|:---|:---:|:---:|
| Süre | 2 saat | 2 saat |
| Soru sayısı | ~17 | ~16 |
| Min. geçme notu | %66 | %67 |
| Format | Performans tabanlı (CLI) | Performans tabanlı (CLI) |
| Geçerlilik | 3 yıl | 2 yıl |
| Ön koşul | Yok | CKA (aktif olmalı) |

## CKA Konu Dağılımı (2024-2026)

| Domain | Ağırlık |
|:---|:---:|
| Storage | %10 |
| Troubleshooting | %30 |
| Workloads & Scheduling | %15 |
| Cluster Architecture & Installation | %25 |
| Services & Networking | %20 |

## CKS Konu Dağılımı

| Domain | Ağırlık |
|:---|:---:|
| Cluster Setup | %15 |
| Cluster Hardening | %15 |
| System Hardening | %10 |
| Minimize Microservice Vulnerabilities | %20 |
| Supply Chain Security | %20 |
| Monitoring, Logging & Runtime Security | %20 |

---

## Hız Komutları — Sınavda Zaman Kazandırır

```bash
# Alias'ları hemen kur (ilk yapılacak iş)
alias k=kubectl
alias kn='kubectl -n'
export do='--dry-run=client -o yaml'

# Zaman kazandıran imperative komutlar
# Deployment oluştur
k create deployment nginx --image=nginx --replicas=3 $do > dep.yaml

# Pod oluştur
k run nginx --image=nginx --port=80 $do > pod.yaml

# Servis expose et
k expose deployment nginx --port=80 --name=nginx-svc $do > svc.yaml

# ConfigMap
k create configmap app-config --from-literal=KEY=VALUE $do > cm.yaml

# Secret
k create secret generic db-secret --from-literal=PASSWORD=secret $do > sec.yaml

# RBAC — Role
k create role pod-reader --verb=get,list,watch --resource=pods $do > role.yaml

# RBAC — RoleBinding
k create rolebinding read-pods --role=pod-reader --user=jane $do > rb.yaml

# ServiceAccount
k create serviceaccount my-sa $do > sa.yaml
```

## CKA Lab Çalışmaları

### Lab 1: Cluster Upgrade

```bash
# Master node güncelleme
kubectl drain k8s-master --ignore-daemonsets
apt-get update && apt-get install -y kubeadm=1.32.0-1.1
kubeadm upgrade apply v1.32.0
apt-get install -y kubelet=1.32.0-1.1 kubectl=1.32.0-1.1
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon k8s-master

# Worker node güncelleme (worker'da çalıştır)
kubectl drain k8s-worker-01 --ignore-daemonsets --delete-emptydir-data
apt-get install -y kubeadm=1.32.0-1.1
kubeadm upgrade node
apt-get install -y kubelet=1.32.0-1.1 kubectl=1.32.0-1.1
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon k8s-worker-01
```

### Lab 2: etcd Yedekleme ve Geri Yükleme

```bash
# Yedek al
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Doğrulama
ETCDCTL_API=3 etcdctl --write-out=table snapshot status /tmp/etcd-backup.db

# Geri yükleme
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-from-backup
```

### Lab 3: NetworkPolicy

```yaml
# Sadece frontend ←’ backend geçiş izni
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
```

### Lab 4: RBAC

```bash
# Sadece pods okuma yetkisi ver
kubectl create role pod-viewer \
  --verb=get,list,watch \
  --resource=pods \
  -n production

kubectl create rolebinding jane-view-pods \
  --role=pod-viewer \
  --user=jane@example.com \
  -n production

# Test et
kubectl auth can-i list pods --as=jane@example.com -n production
```

### Lab 5: PV ve PVC

```yaml
# PersistentVolume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: task-pv
spec:
  capacity:
    storage: 10Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /data/task-pv
---
# PersistentVolumeClaim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: task-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Mi
```

## CKS Lab Çalışmaları

### Lab 1: Pod Security Standards

```bash
# Namespace'e restricted PSS uygula
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

# Güvenli pod tanımı (restricted ile uyumlu)
kubectl run secure-pod --image=nginx:alpine \
  --override-type=merge \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"nginx","image":"nginx:alpine","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
```

### Lab 2: Kyverno ile Güvenlik Politikası

```yaml
# Sadece onaylı imajlara izin ver
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: allowed-images
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-registry
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Sadece trusted-registry.example.com imajları kullanılabilir!"
      pattern:
        spec:
          containers:
          - image: "trusted-registry.example.com/*"
```

### Lab 3: Trivy ile İmaj Tarama

```bash
# İmaj tara
trivy image nginx:latest --severity HIGH,CRITICAL

# Cluster tara
trivy k8s --report summary cluster

# Sonuçları JSON'a aktar
trivy image nginx:latest --format json -o results.json
```

## Sınav Taktikleri

1. **İlk 5 dakika:** `alias k=kubectl; export do='--dry-run=client -o yaml'` çalıştır
2. **Kolay soruları önce çöz** — zor soruları atla, sonra dön
3. **`--dry-run=client -o yaml`** ile önce YAML'a bak, sonra apply et
4. **`kubectl explain`** ile field'ları sorgula: `kubectl explain pod.spec.containers.securityContext`
5. **Bookmarks:** Kubernetes.io/docs her zaman açık olabilir; arama yapabilirsiniz
6. **`kubectl describe` + Events** — hataların %80'i burada açıklanır

---
*← Ana Sayfa*

## Gelişmiş Kubectl Komut Rehberi (Hızlı Erişim)

Aşağıdaki komutlar, günlük operasyonlarda ve sınavlarda ihtiyaç duyulan tüm temel kaynak yönetimini kapsar.

### Favori Komutlar ve Genel İnceleme
```bash
# ===> Namespace ve Genel Kaynaklar
kubectl get namespaces                                  # Tüm namespace'leri listele
kubectl get all -n web-page -o wide                     # Belirli namespace'deki tüm kaynaklar (detaylı)

# ===> Pod ve Deployment Kontrolleri
kubectl get pods -A -o wide                             # Tüm namespace'lerdeki podlar
kubectl get pods -n web-page -o wide                    # Belirli namespace'deki podlar
kubectl get deployments,svc -n web-page                 # Deployment ve Servisleri listele
kubectl describe pod <pod_name> -n web-page             # Pod detaylarını incele

# ===> Depolama (PV / PVC)
kubectl get pv,pvc -n web-page                          # PV ve PVC bilgilerini getir

# ===> Log ve Debug
kubectl logs <pod_name> -n web-page                     # Pod loglarını oku
kubectl logs <pod_name> -n web-page -c <container>      # Çoklu konteynerli podlarda belirli konteyner logu

# ===> Node Detayları
kubectl describe node worker1                           # Node detaylarını ve kapasitesini gör

# ===> YAML Çıktısı Alma
kubectl get pod <pod_name> -n web-page -o yaml          # Mevcut podun YAML manifestini al
```

### Kaynak Yönetimi (Hızlı Komutlar)

| Kaynak | Kısa Ad | Komut Örneği |
|:---|:---:|:---|
| **Nodes** | `no` | `kubectl get no -o wide` |
| **Pods** | `po` | `kubectl get po --show-labels` |
| **Namespaces** | `ns` | `kubectl create ns web-page` |
| **Deployments**| `deploy` | `kubectl scale deploy nginx --replicas=5` |
| **Services** | `svc` | `kubectl get svc -o yaml` |
| **DaemonSets** | `ds` | `kubectl get ds -A` |
| **Events** | `ev` | `kubectl get events -w` |
| **ConfigMaps** | `cm` | `kubectl get cm --all-namespaces` |
| **Secrets** | `secrets`| `kubectl get secrets -o yaml` |

### İmaj Yönetimi (Containerd & K8s)
```bash
# Containerd üzerinde imaj listeleme
sudo ctr images list

# Belirli bir namespace (k8s.io) için imaj çekme
sudo ctr -n k8s.io images pull docker.io/library/nginx:latest

# imajı dosyaya export etme
sudo ctr -n k8s.io images export nginx.tar docker.io/library/nginx:latest

# imajı dosyadan import etme
sudo ctr -n k8s.io images import nginx.tar
```

### Node Operasyonları (Bakım ve Taint)
```bash
# Node'u bakıma al (podları tahliye et)
kubectl drain <node_name> --ignore-daemonsets

# Node'u tekrar schedule edilebilir yap
kubectl uncordon <node_name>

# Node'a Taint ekle
kubectl taint nodes master1 node-role.kubernetes.io/control-plane:NoSchedule

# Node'dan Taint kaldır
kubectl taint nodes master1 node-role.kubernetes.io/control-plane:NoSchedule-
```

### Ağ ve Etkileşim
```bash
# Servisi dışarı aç (Port Forwarding)
kubectl port-forward pod/<pod_name> 8080:80

# Geçici debug podu çalıştır ve içine gir
kubectl run debug-pod --image=busybox --rm -it --restart=Never -- sh

# Çalışan podun içine gir
kubectl exec -it <pod_name> -- /bin/bash
```

---
*← [Ana Sayfa](README.md)*
