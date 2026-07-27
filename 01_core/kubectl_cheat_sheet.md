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

## 4. Hazır YAML Şablon Kütüphanesi

### A. Production Deployment Şablonu

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
  labels:
    app: sample-app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: app-container
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          periodSeconds: 5
```

### B. Service (ClusterIP) Şablonu

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sample-service
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: sample-app
  ports:
  - name: http
    port: 80
    targetPort: 80
```

### C. Ingress Şablonu

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-example-tls
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-service
            port:
              number: 80
```

### D. PersistentVolumeClaim (PVC) Şablonu

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sample-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-ebs-gp3
  resources:
    requests:
      storage: 20Gi
```
