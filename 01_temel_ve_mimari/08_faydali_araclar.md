# Faydalı CLI Araçları ve Kubernetes Ekosistemi

## Araç Kategorileri

| Araç | Kategori | Görev |
|:---|:---:|:---|
| **k9s** | Terminal UI | Cluster'ı görsel olarak yönet |
| **Lens** | Desktop UI | Gelişmiş cluster IDE |
| **Headlamp** | Web UI | Tarayıcı tabanlı hafif dashboard |
| **kubecolor** | CLI | kubectl çıktısını renklendir |
| **kubectl-neat** | CLI | YAML çıktısından gürültüyü temizle |
| **stern** | CLI | Çoklu pod'dan canlı log izleme |
| **kubectx/kubens** | CLI | Context ve Namespace hızla geç |
| **krew** | Plugin | kubectl plugin yöneticisi |
| **Pluto** | CLI | Deprecated API tespiti |
| **Nova** | CLI | Helm chart güncelleme analizi |
| **KubeShark** | Network | Wireshark benzeri API trafiği |

---

## k9s — Terminal'in Grafana'sı

```bash
# Kurulum
brew install k9s   # macOS
choco install k9s  # Windows

# Başlatma
k9s                         # Tüm namespace'ler
k9s -n production           # Belirli namespace
k9s --readonly              # Salt okunur mod (yanlışlıkla silme olmaz)
k9s --context=prod-cluster  # Belirli context
```

**Temel k9s Kısayolları:**

| Kısayol | Görev |
|:---|:---|
| `:po` | Pods listesi |
| `:svc` | Services |
| `:deploy` | Deployments |
| `:pvc` | PVClar |
| `:no` | Nodes |
| `l` | Log görüntüle |
| `s` | Shell bağlan |
| `d` | Describe |
| `e` | Edit |
| `Ctrl+D` | Delete |
| `/` | Filtrele |
| `?` | Tüm kısayollar |

---

## stern — Çoklu Pod Log Takibi

```bash
# Kurulum
brew install stern

# Belirli label'a sahip tüm pod'ların logları
stern -l app=web-app -n production

# Regex ile pod isim filtresi
stern "web-app-.*" -n production

# Belirli konteyner, son 30 dakika
stern web-app --container nginx --since 30m

# JSON format + jq ile filtrele
stern web-app --output json | jq '.message'
```

---

## kubectx & kubens

```bash
# Kurulum
brew install kubectx

# Context yönetimi
kubectx                   # Mevcut context'i göster
kubectx prod-cluster      # Context değiştir
kubectx -                 # Önceki context'e dön

# Namespace yönetimi
kubens production         # Varsayılan namespace değiştir
kubens -                  # Önceki namespace'e dön
```

---

## kubecolor & kubectl-neat

```bash
# kubecolor kurulumu
go install github.com/hidetatz/kubecolor/cmd/kubecolor@latest
alias kubectl="kubecolor"

# kubectl-neat kurulumu (krew üzerinden)
kubectl krew install neat

# YAML çıktısından gürültüyü temizle
kubectl get pod web-pod -o yaml | kubectl neat

# Deployment temiz YAML
kubectl get deployment web-app -o yaml | kubectl neat > clean.yaml
```

---

## Pluto — Deprecated API Tespiti

```bash
# Kurulum
helm plugin install https://github.com/FairwindsOps/pluto

# Cluster'daki deprecated resource'ları tara
kubectl pluto detect-helm
kubectl pluto detect-files -d ./manifests/

# Belirli versiyon kontrolü
pluto detect-helm --target-versions k8s=v1.33
```

---

## Web UI Alternatifleri

### Headlamp (Tarayıcı Tabanlı)

```bash
# Kurulum
kubectl apply -f https://raw.githubusercontent.com/headlamp-k8s/headlamp/main/kubernetes-headlamp/configs/headlamp-plain.yaml

# Admin kullanıcısı ve token oluşturma
kubectl create serviceaccount headlamp-admin -n kube-system
kubectl create clusterrolebinding headlamp-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:headlamp-admin
kubectl create token headlamp-admin -n kube-system

# Port forward ile erişim
kubectl port-forward svc/headlamp -n kube-system 4466:80
# http://localhost:4466
```

### Monokle: YAML Görselleştirme ve Analiz
Karmaşık manifest dosyalarını görselleştirmek, kaynaklar arası bağımlılıkları görmek ve konfigürasyon hatalarını (misconfigurations) tespit etmek için kullanılır.
```bash
# Monokle Desktop indirme: https://monokle.io/download
# CLI ile analiz:
monokle validate ./manifests/
```

---

## Ekosistem Araçları Özeti

| Araç | Kategori | Açıklama |
|:---|:---|:---|
| **Harbor** | Registry | CVE taramalı kurumsal imaj registry |
| **MetalLB** | Networking | Bare-metal LoadBalancer |
| **Longhorn** | Storage | Dağıtık blok depolama |
| **NeuVector** | Security | Full-lifecycle container güvenliği |
| **Pixie** | Observability | eBPF tabanlı otomatik gözlemlenebilirlik |
| **Harvester** | HCI | K8s tabanlı sanallaştırma |
| **Rancher** | Management | Multi-cluster K8s yönetim platformu |

> [!TIP]
> k9s + stern + kubectx kombinasyonu, günlük Kubernetes operasyonlarını dramatik biçimde hızlandırır. Bu üç araç kurulmadan cluster yönetimine başlamayın.

