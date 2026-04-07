# Kubernetes Yönetim Araçları (Operational Tools)

Bu bölümde, Kubernetes cluster operasyonlarını hızlandıran ve görselleştiren popüler araçların (`k9s` ve `Headlamp`) kurulumu ve kullanımı anlatılmaktadır.

---

## 6.1 k9s: Terminal Tabanlı Yönetim

`k9s`, cluster kaynaklarını terminal üzerinden hızlıca izlemek ve yönetmek için kullanılan bir "navigasyon" aracıdır.

### Kurulum

```bash
# Binary olarak indir ve kur
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar -xz
sudo mv k9s /usr/local/bin/

# Versiyon kontrolü
k9s version
```

### Temel Kısayollar

- `?`: Yardım menüsünü açar.
- `0`: Tüm namespace'leri gösterir.
- `d`: Seçili kaynağı describe eder (kubectl describe).
- `l`: Seçili podun loglarını gösterir (kubectl logs).
- `e`: Seçili kaynağı düzenler (kubectl edit).
- `s`: Seçili poda shell ile bağlanır (kubectl exec).
- `/`: Kaynak araması yapar.
- `:ns`: Namespace değiştirmek için komut modu.

---

## 6.2 Headlamp: Kullanıcı Dostu Web Arayüzü

`Headlamp`, Kubernetes için modern, genişletilebilir ve kullanıcı dostu bir web arayüzüdür (Dashboard).

### Kurulum ve Erişim

1. **Servis Hesabı (ServiceAccount) Oluşturma:**
Headlamp'e tam yetki ile bağlanmak için bir admin kullanıcısı oluşturalım.

```bash
# ServiceAccount oluştur
kubectl create serviceaccount headlamp-user -n kube-system

# Cluster Admin yetkisi ver
kubectl create clusterrolebinding headlamp-user-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:headlamp-user
```

2. **Erişim Token'ı Alma:**
Dashboard'a giriş yapmak için bu token'ı kullanacaksınız.

```bash
kubectl create token headlamp-user -n kube-system
```

3. **Servisi NodePort Olarak Açma:**
Eğer Dashboard'a cluster dışından erişmek istiyorsanız:

```bash
kubectl patch svc headlamp -n kube-system -p '{"spec": {"type": "NodePort"}}'

# Portu ve IP'yi öğrenin
kubectl get svc headlamp -n kube-system
```

### Neden Headlamp?
- **Plugin Desteği:** İhtiyaca göre yeni özellikler eklenebilir.
- **Kullanım Kolaylığı:** Kaynaklar arasındaki ilişkiler (Pod -> Service -> Ingress) görsel olarak görülebilir.
- **Güvenlik:** RBAC ile tam uyumludur.
