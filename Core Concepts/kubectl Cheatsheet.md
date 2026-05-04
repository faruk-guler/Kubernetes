# kubectl Cheatsheet

> [!TIP]
> `kubectl` ile her işlemde `-n <namespace>` ekleyerek namespace belirtebilir, `-o wide` ile genişletilmiş çıktı alabilirsiniz.

## Temel Komutlar

```bash
# Cluster bilgisi
kubectl cluster-info
kubectl get nodes -o wide
kubectl version --short

# Bağlam (Context) yönetimi
kubectl config get-contexts
kubectl config use-context <context-name>
kubectl config current-context
```

## Pod Yönetimi

```bash
# Pod listeleme
kubectl get pods                          # default namespace
kubectl get pods -n kube-system           # sistem namespace
kubectl get pods --all-namespaces         # tüm namespace'ler
kubectl get pods -o wide                  # IP ve Node bilgisiyle

# Pod detayı ve loglar
kubectl describe pod <pod-adı>
kubectl logs <pod-adı>
kubectl logs <pod-adı> -c <konteyner-adı> # çok konteynerli pod
kubectl logs <pod-adı> --tail=100 -f      # canlı takip

# Pod içine bağlanma
kubectl exec -it <pod-adı> -- /bin/bash
kubectl exec -it <pod-adı> -c <konteyner> -- sh

# 2026 Standardı: Pod olmadan debug
kubectl debug -it <pod-adı> --image=nicolaka/netshoot --target=<konteyner>

# Pod YAML Manifestini Dışarı Aktarma
kubectl get pod <pod-adı> -o yaml > pod-yedek.yaml
```

## İmaj Yönetimi (ctr & Containerd)

Kubernetes node'ları üzerinde doğrudan imaj yönetimi için `ctr` kullanılır:

```bash
# Tüm imajları listele (k8s.io namespace)
sudo ctr -n k8s.io images list

# İmaj çekme (pull)
sudo ctr -n k8s.io image pull docker.io/library/nginx:latest

# İmajı dosyaya export et
sudo ctr -n k8s.io images export nginx.tar docker.io/library/nginx:latest

# Dosyadan imaj import et
sudo ctr -n k8s.io images import nginx.tar
```

## Kaynak Yönetimi (CRUD)

```bash
# Oluşturma / Uygulama
kubectl apply -f dosya.yaml               # önerilen yöntem
kubectl apply -f ./dizin/                 # dizindeki tüm YAML'lar
kubectl apply -k ./kustomize-dizin/       # Kustomize ile

# Silme
kubectl delete -f dosya.yaml
kubectl delete pod <pod-adı>
kubectl delete pod <pod-adı> --grace-period=0  # zorla sil

# Düzenleme
kubectl edit deployment <dep-adı>         # canlı düzenleme
kubectl patch deployment <dep-adı> -p '{"spec":{"replicas":3}}'

# Durum izleme
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl rollout status deployment/<dep-adı>
```

## Deployment ve Ölçeklendirme

```bash
# Deployment yönetimi
kubectl get deployments
kubectl scale deployment <dep-adı> --replicas=5
kubectl rollout history deployment/<dep-adı>
kubectl rollout undo deployment/<dep-adı>           # son rollback
kubectl rollout undo deployment/<dep-adı> --to-revision=2  # belirli versiyon

# İmaj güncelleme
kubectl set image deployment/<dep-adı> <konteyner>=<yeni-imaj>:v2
```

## Servis ve Port Yönlendirme

```bash
# Servisler
kubectl get services
kubectl get svc -A

# Yerel erişim için port yönlendirme
kubectl port-forward pod/<pod-adı> 8080:80
kubectl port-forward svc/<servis-adı> 8080:80
kubectl port-forward deployment/<dep-adı> 8080:80
```

## ConfigMap ve Secret

```bash
# ConfigMap
kubectl create configmap app-config --from-literal=DB_HOST=mydb
kubectl create configmap app-config --from-file=config.properties
kubectl get configmap app-config -o yaml

# Secret
kubectl create secret generic db-secret \
  --from-literal=password=gizlisifre
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d
```

## Node Yönetimi

```bash
# Node bilgisi
kubectl get nodes
kubectl describe node <node-adı>
kubectl top nodes                          # kaynak kullanımı (metrics-server gerekli)

# Node bakımı
kubectl cordon <node-adı>                  # yeni pod kabul etme
kubectl drain <node-adı> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node-adı>               # geri al

# Taint ve Label Yönetimi
kubectl taint nodes <node-adı> node-role.kubernetes.io/control-plane:NoSchedule  # Taint ekle
kubectl taint nodes <node-adı> node-role.kubernetes.io/control-plane:NoSchedule- # Taint kaldır
kubectl label node <node-adı> disktype=ssd        # Etiket ekle
kubectl label node <node-adı> disktype-           # Etiket kaldır
```

## Hızlı Tanı (Troubleshooting One-Liners)

```bash
# Tüm namespace'lerde sorunlu pod'lar
kubectl get pods -A --field-selector=status.phase!=Running

# Son olaylar
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# En çok kaynak kullanan pod'lar
kubectl top pods -A --sort-by=cpu

# Pod'un neden çalışmadığını öğren
kubectl describe pod <pod-adı> | grep -A10 Events

# Tüm kaynakları listele
kubectl api-resources

# YAML formatında çıktı al (yedek için)
kubectl get all -n <namespace> -o yaml > backup.yaml

---

## Gelişmiş Sorgulama (JSONPath & Custom Columns)

Standart çıktıların yetmediği durumlarda veriyi filtrelemek için kullanılır:

```bash
# Sadece Pod isimlerini listele
kubectl get pods -o jsonpath='{.items[*].metadata.name}'

# Pod IP'lerini ve Node isimlerini tablo olarak al
kubectl get pods -o custom-columns=POD_NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName

# Sadece belirli bir imajı kullanan pod'ları bul
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Secret içeriğini base64 decode ederek doğrudan oku
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d
```

## Daha Fazla Kısaltma (Short Names)

| Kaynak | Kısa Ad |
|:---|:---|
| `persistentvolumes` | `pv` |
| `serviceaccounts` | `sa` |
| `statefulsets` | `sts` |
| `daemonsets` | `ds` |
| `endpoints` | `ep` |
| `rolebindings` | `rb` |
| `clusterrolebindings` | `crb` |

---

---

## Faydalı CLI Araçları

| Araç | Görev |
|:-----|:------|
| **k9s** | Terminal UI — cluster'ı görsel yönet |
| **stern** | Çoklu pod'dan canlı log izleme |
| **kubectx/kubens** | Context ve namespace hızlı geçiş |
| **kubecolor** | kubectl çıktısını renklendir |
| **kubectl-neat** | YAML çıktısından gürültüyü temizle |
| **Pluto** | Deprecated API tespiti |
| **Headlamp** | Tarayıcı tabanlı hafif dashboard |

```bash
# k9s
brew install k9s
k9s -n production          # Namespace ile başlat
k9s --readonly             # Salt okunur (yanlışlıkla silme olmaz)
# Kısayollar: :po (pods) :svc (services) :no (nodes) l (log) s (shell) d (describe)

# stern — çoklu pod log
brew install stern
stern -l app=api -n production          # Label ile tüm pod'lar
stern "api-.*" -n production            # Regex
stern api --container nginx --since 30m # Container + zaman filtresi

# kubectx / kubens
brew install kubectx
kubectx prod-cluster     # Context geç
kubectx -                # Önceki context
kubens production        # Namespace geç

# kubectl-neat — temiz YAML
kubectl krew install neat
kubectl get pod web -o yaml | kubectl neat

# Pluto — deprecated API bul
pluto detect-helm --target-versions k8s=v1.33
pluto detect-files -d ./manifests/
```

> [!TIP]
> **k9s + stern + kubectx** kombinasyonu günlük K8s operasyonlarını dramatik biçimde hızlandırır. Bu üç araç kurulmadan cluster yönetimine başlamayın.
