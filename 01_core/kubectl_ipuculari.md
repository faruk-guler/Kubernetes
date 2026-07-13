# kubectl Aracının Verimli Kullanımı

Kümenizi kurduğunuza göre artık ona komutlar vermenin zamanı geldi. Tıpkı bir Linux sunucusuna bağlanıp `bash` kullanmak gibi, Kubernetes kümesiyle etkileşime geçmek için de **kubectl** (kube-control) adlı resmi CLI aracını kullanırız.

Bu bölümde kubectl'in temellerinden başlayıp, günlük operasyonlarınızı ışık hızına çıkaracak "Zero to Hero" yardımcı araçlara (`k9s`, `krew`, `Lens`) kadar uzanacağız.

---

## 1. Temel kubectl Kullanımı

`kubectl`, arka planda Kubernetes API Server'ına REST çağrıları yapar. Tüm komutlar şu genel sözdizimini izler:
`kubectl [işlem] [kaynak_türü] [kaynak_adı] [bayraklar]`

**En Çok Kullanılan Komutlar:**

```bash
# Kümedeki nodeları listele
kubectl get nodes

# Çalışan uygulamaları (pod'ları) listele
kubectl get pods

# Detaylı bilgi al (debug için çok önemlidir)
kubectl describe pod <pod-adi>

# Bir pod'un canlı loglarını (-f: follow) oku
kubectl logs -f <pod-adi>

# Bir pod'un içine girip komut satırı (shell) başlat
kubectl exec -it <pod-adi> -- /bin/sh

# Bir kaynağı YAML dosyasından kümeye yükle
kubectl apply -f deployment.yaml

# Bir kaynağı sil
kubectl delete pod <pod-adi>
```

> **kubeconfig Nedir?**
> `kubectl` aracı, kümeye nasıl bağlanacağını ve hangi şifreyle/token'la giriş yapacağını `~/.kube/config` adlı dosyadan okur. Birden fazla kümeniz (Dev, Test, Prod) varsa, bu dosya içerisinde "Context"ler arası geçiş yaparak tek bilgisayardan tüm kümeleri yönetebilirsiniz.

---

## 2. Gelişmiş Komut Satırı: krew ve Eklentiler

Tıpkı işletim sisteminize program kurduğunuz gibi, `kubectl` aracınıza da eklentiler (plugin) kurabilirsiniz. Bunun için resmi eklenti yöneticisi **krew** kullanılır.

Krew kurulduktan sonra hayat kurtaran bazı eklentiler:

```bash
# Plugin kurma komutu
kubectl krew install <plugin-adi>

# Önerilen Pluginler:
# ctx: Kümeler (context) arası saniyeler içinde geçiş yapar
kubectl ctx prod-cluster

# ns: Namespace'ler arası hızlı geçiş yapar
kubectl ns kube-system

# neat: Çıktılardaki gereksiz, sistem tarafından eklenmiş uzun kodları temizler
kubectl get pod web -o yaml | kubectl neat

# tree: Kaynakların birbirine olan bağlılığını (hiyerarşisini) ağaç gibi gösterir
kubectl tree deployment api
```

---

## 3. Terminal Uzmanlığı: k9s

Eğer her gün Kubernetes yönetiyorsanız, sürekli `kubectl get pods` yazmak yorucu olacaktır. Terminal tabanlı grafik arayüze sahip **k9s**, Kubernetes operasyonlarında endüstri standardı haline gelmiştir.

```bash
# macOS için kurulum
brew install k9s
```

`k9s` terminalde çalışır; ok tuşlarıyla pod'lar arasında gezinebilir, logları görmek için `L` tuşuna, içine girmek için `S` tuşuna, silmek için `Ctrl+D` tuşuna basabilirsiniz. Fareye dokunmadan bir kümedeki her şeyi saniyeler içinde yönetmenizi sağlar.

---

## 4. Masaüstü ve Web Arayüzleri

Komut satırı sevmeyenler veya kümeyi devasa bir ekranda görselleştirmek isteyenler için harika araçlar mevcuttur:

* **Lens / OpenLens:** Kubernetes için tam teşekküllü masaüstü IDE'sidir. Birden fazla kümeyi grafik arayüzle, harika grafikler eşliğinde yönetmenizi sağlar.
* **Headlamp:** Daha hafif, güvenli ve tarayıcı tabanlı bir web arayüzüdür. Kümeye doğrudan kurulur ve ekiple paylaşmak için idealdir.
* **KubeShark:** Kubernetes için Wireshark'tır. Pod'lar arasındaki trafiği dinler, kim kime hangi isteği gönderdi grafiksel olarak saniyesi saniyesine gösterir (L7 trafik analizi).
* **Monokle:** Yazdığınız karmaşık YAML dosyalarını kümeye göndermeden önce masaüstünde görselleştirip hatalarını bulan harika bir analiz aracıdır.

---

## Özet

`kubectl` Kubernetes'in alfabesidir. Onu bilmek zorunludur. Ancak "Zero to Hero" vizyonu, günlük işleri otomatize etmeyi gerektirir. `k9s` gibi terminal araçları ve `Lens` gibi masaüstü uygulamalarıyla operasyonel hızınızı katlayabilirsiniz.

Böylece **Bölüm 1: Temeller ve Mimari** kısmını tamamladık. Konteynerleri öğrendik, orkestrasyonu anladık, mimariyi inceledik ve ortamımızı kurup aracımızı seçtik.

Bir sonraki bölümde, artık kendi kodumuzu bu kümenin üzerinde çalıştırmayı öğreneceğimiz **Bölüm 2: Temel Nesneler ve İş Yükleri (Workloads)** serüvenine, yani Pod'ların dünyasına giriş yapıyoruz!
