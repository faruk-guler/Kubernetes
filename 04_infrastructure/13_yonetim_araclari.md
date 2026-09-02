# Kubernetes Yönetim Araçları (Management Tools)

Bir Kubernetes kümesini sadece ham `kubectl` komutlarıyla yönetmeye çalışmak, koca bir yolcu uçağını sadece komut satırından uçurmaya benzer. Teorik olarak her şeyi yapabilirsiniz; fakat acil bir kriz anında, onlarca pod çökerken veya diskler dolarken anlık durumları hızlıca görebilmek için kokpitteki gösterge panellerine, görsel arıza lambalarına ve hızlı yönetim araçlarına ihtiyaç duyarsınız.

Bu bölümde, günlük Kubernetes operasyonlarınızı hızlandıran, kriz anlarında saniyeler içinde pod'ların kalbine inmenizi sağlayan en popüler terminal UI, masaüstü IDE, eklenti yöneticileri ve ağ izleme araçlarını ele alacağız.

---

## 1. k9s — Terminal Tabanlı Küme Yönetimi

**k9s**, Kubernetes kümelerinizi gerçek zamanlı olarak izlemenizi, yönetmenizi ve sorun gidermenizi sağlayan son derece hızlı ve popüler bir terminal arayüzüdür (CLI Dashboard).

```bash
# Kurulum (Windows)
choco install k9s
# Kurulum (macOS)
brew install derailed/k9s/k9s

# k9s başlatma
k9s                           # Varsayılan context ile açar
k9s -n production             # Sadece production namespace'ini izler
k9s --context dev-cluster     # Belirli bir context ile açar
k9s --readonly                # Salt okunur mod (Kazara pod/nesne silmeyi engeller)
```

### Temel Navigasyon Kısayolları

| Kısayol | İşlev / Ekran Geçişi |
|:---|:---|
| `:po` | Pod listesini gösterir |
| `:svc` | Service listesini gösterir |
| `:deploy` | Deployment listesini gösterir |
| `:ns` | Namespace değiştirme listesini açar |
| `:no` | Düğüm (Node) listesini gösterir |
| `:pvc` | PersistentVolumeClaim listesini gösterir |
| `/` | Bulunulan ekranda arama/filtreleme yapar |
| `l` | Seçili pod'un loglarını canlı akışla izletir |
| `s` | Seçili pod'un içine kabuk (shell) bağlantısı açar |
| `d` | Seçili kaynağın detaylarını gösterir (`describe`) |
| `e` | Seçili kaynağın YAML dosyasını düzenler (`edit`) |
| `Ctrl + D` | Seçili nesneyi siler (`delete`) |
| `Ctrl + K` | Seçili nesneyi zorla sonlandırır (`kill - force delete`) |
| `0` | Tüm namespace'leri filtreler |

---

## 2. Lens / OpenLens — Masaüstü Kubernetes IDE

**Lens**, küme yöneticileri ve platform mühendisleri için geliştirilmiş en popüler masaüstü görsel yönetim aracıdır.

* **OpenLens:** Lens'in tamamen ücretsiz ve açık kaynaklı dağıtımıdır.
* **Faydaları:** Çoklu küme bağlantılarını tek pencerede yönetir. Pod loglarını, terminal bağlantılarını ve Helm depolarını tek tıkla açar. Düğümlerin CPU/RAM durumlarını yerleşik grafiklerle görselleştirir.

```bash
# Windows Kurulumu
choco install openlens

# macOS Kurulumu
brew install --cask openlens
```

---

## 3. Headlamp — Web Tabanlı Küme Arayüzü

**Headlamp**, tarayıcı üzerinden çalışan, RBAC uyumlu ve hafif bir Kubernetes yönetim paneli (dashboard) alternatifidir.

```bash
# Helm ile sisteme kurma
helm repo add headlamp https://headlamp-k8s.github.io/headlamp/
helm install headlamp headlamp/headlamp \
  --namespace kube-system \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=headlamp.company.com

# Yerel test için port-forward ile erişme
kubectl port-forward svc/headlamp -n kube-system 4466:80
# Tarayıcıdan http://localhost:4466 adresinden erişebilirsiniz.
```

---

## 4. `krew` ve Popüler `kubectl` Eklentileri

**krew**, `kubectl` komut satırı aracına yeni yetenekler ekleyen resmi eklenti (plugin) yöneticisidir.

```bash
# Krew kurulumu sonrasında kullanabileceğiniz en popüler eklentiler:
kubectl krew install neat      # YAML çıktılarındaki gereksiz sistem metadata'larını temizler
kubectl krew install tree      # Kaynakların hiyerarşik ilişkisini gösterir
kubectl krew install images    # Pod'larda hangi imajların çalıştığını listeler
kubectl krew install df-pv     # Kalıcı disklerin (PV) doluluk oranlarını gösterir
kubectl krew install who-can   # RBAC yetkilerini sorgular (Kim neyi silebilir?)
kubectl krew install stern     # Birden fazla pod'un logunu tek ekranda birleştirir (Log tailing)
```

### Örnek Eklenti Kullanımları

```bash
# 1. neat eklentisi ile sadeleştirilmiş YAML alma
kubectl get deployment my-api -o yaml | kubectl neat > clean-deployment.yaml

# 2. tree eklentisi ile API bağımlılık ağacını görme
kubectl tree deployment my-api -n production

# 3. stern ile adında 'api' geçen tüm podların loglarını canlı izleme
stern "api-.*" -n production --since 15m
```

---

## 5. Reloader — ConfigMap ve Secret Değişim Yönetimi

Kubernetes'te bir ConfigMap veya Secret güncellendiğinde, bu değerleri kullanan podlar otomatik olarak yeniden başlamaz. Değişikliklerin yansıması için podların el ile tetiklenmesi gerekir.

**Reloader**, kümedeki ConfigMap veya Secret nesnelerini izleyen ve bir değişiklik algıladığında, bu nesneleri kullanan Deployments/StatefulSets/DaemonSets nesnelerini otomatik olarak sıfır kesintiyle (rolling-restart) yeniden başlatan akıllı bir denetleyicidir.

```bash
# Helm ile kurulum
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader \
  --namespace reloader \
  --create-namespace
```

### Deployment Üzerinde Kullanımı

İlgili Deployment nesnesinin `annotations` bölümüne şu etiket eklenerek aktif edilir:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true" # CM veya Secret değiştiğinde bu deployment'ı yeniden başlat
```

---

## 6. KubeShark — Kubernetes Ağ Trafiği Analizcisi

**KubeShark**, Kubernetes podları arasındaki HTTP, gRPC, DNS ve TCP trafiğini gerçek zamanlı olarak izlemenizi, filtrelemenizi ve analiz etmenizi sağlayan (Wireshark benzeri) bir ağ koklayıcıdır (network sniffer).

```bash
# Kurulum (macOS)
brew install kubeshark

# Tüm kümenin L7 ağ trafiğini yakalayıp tarayıcıda görselleştirme
kubeshark tap

# Sadece belirli bir namespace ve regex filtresiyle izleme
kubeshark tap "api-.*" -n production
```

*Görsel arayüz üzerinden `http.request.method == "POST" && http.response.statusCode >= 500` gibi filtreler yazarak servisler arası API arızalarını anında teşhis edebilirsiniz.*

---

## 7. Yönetim Araçları Karşılaştırma Özeti

| Araç | Türü | En İdeal Kullanım Alanı |
|:---|:---|:---|
| **k9s** | Terminal UI | Günlük hızlı operasyonlar, sorun giderme ve terminal hızında yönetim. |
| **OpenLens** | Masaüstü IDE | Çoklu cluster yönetimi ve görsel metrik takibi. |
| **Headlamp** | Web Arayüzü | Ekip içi paylaşımlı ve OIDC korumalı merkezi yönetim paneli. |
| **Reloader** | Controller | ConfigMap ve Secret değişikliklerinde sıfır kesintili otomatik güncelleme. |
| **KubeShark** | Ağ Analizcisi | Servisler arası HTTP/gRPC API çağrılarının hata tespiti (Debugging). |

---

## Özet

Kubernetes altyapısını yönetirken doğru araçları seçmek ekiplerin müdahale sürelerini ciddi oranda düşürür. Günlük operasyonlar için **k9s** komut satırı hızı sağlarken, ağ sorunlarında **KubeShark** ve konfigürasyon güncellemelerinde **Reloader** gibi denetleyiciler süreçleri tamamen otomatize etmenize olanak tanır.
