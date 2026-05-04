# CKA / CKAD / CKS Sertifikasyon Rehberi

Linux Foundation'ın üç Kubernetes sertifikası pratik, terminal tabanlı sınavlardır. Çoktan seçmeli soru yoktur — gerçek cluster üzerinde görevler tamamlanır.

---

## Sertifikalara Genel Bakış

| Sertifika | Tam Ad | Kitle | Süre | Geçme |
|:----------|:-------|:------|:-----|:------|
| **CKA** | Certified Kubernetes Administrator | Cluster yöneticileri | 2 saat | %66 |
| **CKAD** | Certified K8s Application Developer | Uygulama geliştiriciler | 2 saat | %66 |
| **CKS** | Certified K8s Security Specialist | Güvenlik odaklı (CKA gerekir) | 2 saat | %67 |

---

## CKA — Konu Ağırlıkları

```
Cluster Architecture, Installation & Configuration : %25
  - kubeadm kurulum ve upgrade
  - etcd backup/restore
  - RBAC
  - Kubeconfig yönetimi

Workloads & Scheduling                            : %15
  - Deployment, DaemonSet, StatefulSet
  - Resource limits, LimitRange, ResourceQuota
  - Node affinity, taints/tolerations

Services & Networking                             : %20
  - Service türleri (ClusterIP, NodePort, LB)
  - Ingress ve Ingress Controller
  - NetworkPolicy
  - CoreDNS

Storage                                           : %10
  - PV, PVC, StorageClass
  - Access modes

Troubleshooting                                   : %30  ← En ağır bölüm!
  - Pod/container sorunlarını çözme
  - Node sorunları (kubelet, network)
  - Cluster bileşen sorunları
```

---

## CKAD — Konu Ağırlıkları

```
Application Design and Build                      : %20
  - Multi-container pod desenleri (sidecar, init)
  - Job, CronJob
  - Dockerfile yazmak
  - Distroless image

Application Deployment                            : %20
  - Deployment stratejileri
  - Helm chart'ı değiştirme ve deploy
  - Kustomize

Application Observability and Maintenance         : %15
  - Liveness/Readiness/Startup probe
  - kubectl debug
  - Log analizi

Application Environment, Config & Security       : %25
  - ConfigMap, Secret
  - ServiceAccount
  - SecurityContext
  - Resource limits

Services & Networking                             : %20
  - Service, Ingress
  - NetworkPolicy
```

---

## CKS — Konu Ağırlıkları

```
Cluster Setup                                     : %10
  - CIS Benchmark
  - Network Policy
  - Ingress + TLS

Cluster Hardening                                 : %15
  - RBAC best practices
  - ServiceAccount güvenliği
  - K8s API güvenliği

System Hardening                                  : %15
  - OS seviyesi kısıtlamalar
  - AppArmor, Seccomp profilleri
  - Kernel module kısıtlaması

Minimize Microservice Vulnerabilities             : %20
  - Pod Security Standards
  - OPA/Kyverno
  - Secret yönetimi (Vault)
  - Runtime sandbox (gVisor, Kata)

Supply Chain Security                             : %20
  - Image scanning (Trivy)
  - Image signing (Cosign)
  - Admission controller

Monitoring, Logging and Runtime Security          : %20
  - Falco behavioral analysis
  - Audit log analizi
  - Container runtime güvenliği
```

---

## Sınav Ortamı ve Taktikler

### Ortam

```bash
# Sınavda birden fazla cluster var
# Her görevde hangi cluster → kubectl config use-context belirtilir

# Örnek: "cluster1'de aşağıdaki görevi tamamlayın"
kubectl config use-context cluster1

# Çözüm sonrası context'i kontrol et!
kubectl config current-context
```

### En Önemli Taktikler

```bash
# 1. kubectl explain — YAML şemasını bilmiyorsan
kubectl explain pod.spec.containers.resources
kubectl explain deployment.spec.strategy.rollingUpdate
kubectl explain networkpolicy.spec

# 2. --dry-run ile YAML üret, düzenle, uygula
kubectl create deployment web --image=nginx:1.25 \
  --replicas=3 --dry-run=client -o yaml > deploy.yaml
vim deploy.yaml
kubectl apply -f deploy.yaml

# 3. Kısayollar — zaman kazandır
alias k=kubectl
export do="--dry-run=client -o yaml"
k create deploy web --image=nginx $do > web.yaml

# 4. kubectl imperative komutlar ezberle
k run pod1 --image=nginx --port=80
k expose pod pod1 --port=80 --type=NodePort
k create configmap myconfig --from-literal=key=value
k create secret generic mysecret --from-literal=pass=1234
k create serviceaccount mysa
k create role myrole --verb=get,list --resource=pods
k create rolebinding myrb --role=myrole --serviceaccount=default:mysa

# 5. kubectl edit — hızlı değişiklik
k edit deployment/web
```

---

## CKA Kritik Komutlar

```bash
# etcd backup (sınav favorisi!)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Sertifika yenileme
kubeadm certs renew all
kubeadm certs check-expiration

# Node upgrade (kubeadm)
# 1. Control plane:
apt-get install kubeadm=1.31.0-00
kubeadm upgrade plan
kubeadm upgrade apply v1.31.0
apt-get install kubelet=1.31.0-00 kubectl=1.31.0-00
systemctl restart kubelet

# 2. Worker node:
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# (Worker node'da)
apt-get install kubeadm=1.31.0-00
kubeadm upgrade node
apt-get install kubelet=1.31.0-00
systemctl restart kubelet
# (Control plane'de)
kubectl uncordon <node>

# NetworkPolicy — tüm trafiği engelle, sadece 80'e izin ver
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-only
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes: [Ingress]
  ingress:
  - ports:
    - port: 80
EOF
```

---

## CKAD Kritik Komutlar

```bash
# Multi-container pod (sidecar)
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-pod
spec:
  containers:
  - name: main
    image: nginx
  - name: sidecar
    image: busybox
    command: ["sh", "-c", "while true; do echo log; sleep 5; done"]
EOF

# Job — completion index ile
kubectl create job pi --image=perl:5.34 -- perl -Mbignum=bpi -wle 'print bpi(2000)'

# Liveness probe ile pod
k run probe-pod --image=nginx --dry-run=client -o yaml | \
  kubectl set resources -f - --requests=cpu=100m,memory=128Mi --dry-run=client -o yaml > pod.yaml

# ConfigMap'ten env
kubectl create configmap app-config \
  --from-literal=DB_HOST=postgres \
  --from-literal=DB_PORT=5432

kubectl set env deployment/web --from=configmap/app-config
```

---

## CKS Kritik Komutlar

```bash
# Trivy ile image tarama
trivy image nginx:latest --severity HIGH,CRITICAL

# Falco kuralı
cat >> /etc/falco/falco_rules.local.yaml << 'EOF'
- rule: Detect Shell in Container
  desc: Shell başlatıldı
  condition: spawned_process and container and shell_procs
  output: "Shell açıldı: %container.name %proc.cmdline"
  priority: WARNING
EOF

# AppArmor profili uygula
aa-genprof /usr/bin/node     # Profil oluştur
kubectl annotate pod <pod> \
  container.apparmor.security.beta.kubernetes.io/app=localhost/my-profile

# Audit policy
cat /etc/kubernetes/audit-policy.yaml
# kubectl api-server flag: --audit-policy-file=/etc/kubernetes/audit-policy.yaml
```

---

## Önerilen Hazırlık Planı

| Hafta | CKA | CKAD | CKS |
|:------|:----|:-----|:----|
| 1-2 | Cluster kurulum, etcd, RBAC | Pod, Deployment, Service | CKA tekrarı + Network Policy |
| 3 | Networking, Storage | ConfigMap, Secret, Probe | Security Context, PSA |
| 4 | Troubleshooting (ağırlıklı) | Helm, Job, Multi-container | Falco, Trivy, OPA |
| 5 | killer.sh mock sınavı (2x) | killer.sh mock sınavı (2x) | killer.sh mock sınavı (2x) |

> [!TIP]
> **killer.sh** — Resmi sınav simülatörü. Her sertifika alımında 2 oturum hakkı veriliyor. Gerçek sınavdan daha zor, bu yüzden orada 70+ alıyorsan sınavı geçersin.

> [!IMPORTANT]
> Sınavda **bookmarks** izin veriliyor. Kubernetes resmi dokümantasyonuna (`kubernetes.io/docs`) bookmark ekle: etcd backup, kubeadm upgrade, NetworkPolicy örnekleri, RBAC manifest'leri.
