# Minikube ile Yerel Geliştirme

Minikube, yerel bilgisayarınızda tek düğümlü (single-node) bir Kubernetes kümesi çalıştırmanın en popüler ve resmi olarak desteklenen yollarından biridir. Özellikle "Addon" (Eklenti) ekosistemi sayesinde yeni başlayanlar için yapılandırması en kolay araçtır.

---

## 1. Minikube Kurulumu

Minikube, arka planda bir sanal makine veya konteyner sürücüsü (Docker, VirtualBox, KVM, Hyper-V) kullanır. Günümüzde en yaygın yaklaşım **Docker sürücüsünü** kullanmaktır.

### Gereksinimler
- Docker Desktop (veya sadece Docker Engine)
- `kubectl` CLI aracı

### Windows (winget ile)
```powershell
winget install minikube
```

### Linux (curl ile)
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

### macOS (Homebrew ile)
```bash
brew install minikube
```

---

## 2. Küme Başlatma ve Temel Komutlar

Docker sürücüsü ile yeni bir küme başlatmak için:

```bash
minikube start --driver=docker
```

Kümenize spesifik CPU ve RAM limitleri atamak isterseniz:
```bash
minikube start --memory=4096 --cpus=2
```

Mevcut Minikube durumunu kontrol etmek için:
```bash
minikube status
```

Minikube'u durdurmak ve tamamen silmek için:
```bash
minikube stop
minikube delete
```

---

## 3. Minikube Eklentileri (Addons)

Minikube'un en güçlü yanı tek komutla etkinleştirilebilen eklentileridir. Standart bir Kubernetes kümesinde YAML dosyalarıyla uğraşarak kuracağınız araçları, Minikube'da `enable` komutuyla aktif edebilirsiniz.

Kullanılabilir tüm eklentileri listelemek için:
```bash
minikube addons list
```

### Önemli Eklentiler:

1. **Dashboard (Web Arayüzü):**
   ```bash
   minikube addons enable dashboard
   minikube dashboard
   ```
   Bu komut tarayıcınızda otomatik olarak Kubernetes yönetim panelini açar.

2. **Ingress (Nginx Ingress Controller):**
   Uygulamalarınızı dışarı açmak (Routing) için Ingress çok kritiktir.
   ```bash
   minikube addons enable ingress
   ```

3. **Metrics Server:**
   `kubectl top pod` komutunu kullanarak CPU/RAM kullanımını görmek ve HPA (Horizontal Pod Autoscaler) kullanabilmek için gereklidir.
   ```bash
   minikube addons enable metrics-server
   ```

---

## 4. Dışarıdan Erişebilirlik (Port Yönlendirme)

Minikube, yerel bilgisayarınızda izole bir IP adresinde (genellikle `192.168.49.2`) çalışır. Kümedeki Servislere `localhost` üzerinden erişmek için **minikube tunnel** veya **port-forward** kullanmalısınız.

### LoadBalancer Servisleri İçin (Tunnel)
Eğer `type: LoadBalancer` olan bir servisiniz varsa, ona dış IP atanması için tünel başlatmalısınız (Bu komut ayrı bir terminalde sürekli açık kalmalıdır):
```bash
minikube tunnel
```
Artık `localhost:80` üzerinden uygulamanıza erişebilirsiniz.

### NodePort veya ClusterIP Servisleri İçin (Port-Forward)
```bash
kubectl port-forward svc/benim-servisim 8080:80
```

---

## 5. Yerel Docker İmajlarını Minikube İçinde Kullanmak

En sık karşılaşılan sorun, yerel olarak `docker build` ile oluşturduğunuz bir imajı, Minikube kümesinin görememesidir. Çünkü Minikube'un içindeki Docker daemon'u, bilgisayarınızdaki Docker daemon'undan **farklıdır**.

Bu sorunu çözmenin iki yolu vardır:

**Yöntem 1: İmajı Minikube içine yüklemek (Önerilen)**
```bash
minikube image load benim-imajim:latest
```

**Yöntem 2: Terminalinizin Docker ortamını Minikube'a bağlamak**
Bu komutu çalıştırdıktan sonra yapacağınız tüm `docker build` işlemleri doğrudan Minikube'un içerisine kaydedilir:
```bash
eval $(minikube docker-env)
```

## Özet
Minikube, özellikle Kubernetes'e yeni başlayanlar ve karmaşık CI/CD otomasyonlarından ziyade tekil mikroservislerini lokalde test etmek isteyen geliştiriciler için **en iyi** seçimdir.
