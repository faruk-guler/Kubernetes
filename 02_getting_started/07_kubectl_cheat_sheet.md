# Kubectl ve YAML Cheat Sheet

Bu doküman, günlük sistem yönetimi çalışmalarında ve CKA/CKAD/CKS sınavlarında en çok ihtiyaç duyacağınız `kubectl` komutlarını, imperative (emredici) taslak üretme kısayollarını ve hazır kopyala-yapıştır YAML şablon kütüphanesini içerir.

---

## 1. Terminal Kısayolları (Aliases & Autocomplete)

Sınavlarda veya günlük çalışmalarda her defasında `kubectl` yazmak yerine aşağıdaki alias tanımlamalarını kullanabilirsiniz:

```bash
# Bash Otomatik Tamamlama ve 'k' Alias Tanımlama
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k

# CKA Sınav Hız Değişkeni (YAML Taslağı Üretici)
export do="--dry-run=client -o yaml"
```

---

## 2. Hızlı Imperative Nesne Oluşturma (YAML Yazmadan Tek Satırda)

YAML yazmak yerine terminalden saniyeler içinde nesne oluşturmak veya taslak YAML üretmek için:

```bash
# 1. Pod Oluşturma ve Taslak Üretme
k run nginx-pod --image=nginx:alpine
k run redis-pod --image=redis:alpine $do > pod.yaml

# 2. Deployment ve Replica Sayısı Belirtme
k create deployment web-app --image=nginx:1.25 --replicas=3
k create deployment api-app --image=node:18 $do > deployment.yaml

# 3. Servis İle Dışarı Açma (Expose)
k expose deployment web-app --port=80 --target-port=8080 --name=web-service --type=ClusterIP
k expose pod nginx-pod --port=80 --type=NodePort --name=nginx-nodeport

# 4. ConfigMap ve Secret Üretme
k create configmap app-config --from-literal=ENV=prod --from-literal=DEBUG=false
k create secret generic db-pass --from-literal=password='Secret123!'
```

---

## 3. Canlı Küme İnceleme ve Kaynak İzleme Komutları

```bash
# Tüm Namespace'lerdeki Pod'ları genişlik (IP ve Düğüm adları) ile listele
k get pods -A -o wide

# Kaynak kullanımı canlı izleme (Metrics Server gerekli)
k top nodes
k top pods --sort-by=cpu -n production
k top pods --sort-by=memory -n production

# Canlı Log Takibi ve Önceki Çöken Log
k logs -f <pod-name> -c <container-name> -n production
k logs <pod-name> --previous # Çöken önceki konteyner logu

# Pod/Node Olay Geçmişini (Events) İnceleme
k get events --sort-by='.metadata.creationTimestamp' -n production
```

---

## 4. Kubectl ile Hızlı YAML İskeleti Üretme (`--dry-run=client`)

Profesyonel Kubernetes mühendisleri YAML dosyalarını sıfırdan elle yazmazlar; `kubectl`'in `--dry-run=client -o yaml` yeteneğini kullanarak hatasız bir iskelet üretir ve üzerinde düzenleme yaparlar:

```bash
# 1. Deployment iskeleti üretip dosyaya yazma:
kubectl create deployment web-app --image=nginx:1.27-alpine --replicas=3 --dry-run=client -o yaml > deployment.yaml

# 2. Deployment için Service (ClusterIP) iskeleti üretme:
kubectl expose deployment web-app --port=80 --target-port=8080 --dry-run=client -o yaml > service.yaml

# 3. ConfigMap iskeleti üretme:
kubectl create configmap app-config --from-literal=APP_ENV=prod --dry-run=client -o yaml > configmap.yaml

# 4. Tek seferlik Job iskeleti üretme:
kubectl create job db-migrate --image=migrate-tool:v1 --dry-run=client -o yaml -- ./migrate.sh > job.yaml

# 5. Namespace ve ResourceQuota iskeleti:
kubectl create namespace staging --dry-run=client -o yaml > namespace.yaml
```
