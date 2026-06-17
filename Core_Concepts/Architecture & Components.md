# Kubernetes Mimarisi ve Bileşenleri

## Control Plane Bileşenleri

Control Plane, cluster'ın karar verme ve yönetim merkezidir. Üretim ortamlarında **yüksek erişilebilirlik (HA)** sağlamak amacıyla en az 3 Control Plane node'undan oluşan bir yapı kurulur.

---

### kube-apiserver (API Server)

* **Kubernetes'in Beyni ve İletişim Kavşağı:** Cluster'ın dış dünyaya açılan tek kapısıdır. Adeta her talebi karşılayan, yetki kontrolü yapan ve diğer tüm bileşenleri organize eden bir gümrük memuru gibidir. Tüm `kubectl` komutları ve iç bileşen iletişimleri bu REST API üzerinden gerçekleşir.
* Kimlik doğrulama (Authentication), yetkilendirme (Authorization) ve mutasyon/validasyon işlemlerini yürütür.
* Cluster içindeki tüm durum değişiklikleri mutlaka API Server üzerinden geçmek ve doğrulanmak zorundadır.

---

### etcd

* **Cluster Hafızası ve Kara Kutusu:** Cluster'ın tüm anlık durumunu (desired state) saklayan dağıtık ve tutarlı bir key-value veritabanıdır. Kubernetes cluster'ı bir insan olsaydı, etcd onun tüm anılarını ve kararlarını saklayan hafıza merkezi olurdu.
* **Kritik:** etcd'nin yedeği, cluster'ın yedeğidir. Tüm konfigürasyon, nesne tanımları ve canlı kaynak bilgileri burada tutulur.
* Raft konsensüs algoritmasını kullanır; bu yüzden yüksek erişilebilirlik (HA) mimarilerinde tutarlılığı korumak adına her zaman **tek sayılı node** (3 veya 5) kurulumu gerektirir.

---

### kube-scheduler

* **Zamanlayıcı ve Yerleştirici:** Yeni oluşturulan Pod'ların hangi node üzerinde çalıştırılacağına karar veren akıllı bir yerleşim planlayıcısıdır. Pod'ları en uygun evlere (node'lara) yerleştiren profesyonel bir emlakçı gibi çalışır.
* **Çalışma Algoritması (İki Aşamalı):**
    1.  **Filtering (Predicates / Filtreleme):** Pod'un kaynak gereksinimlerini karşılamayan (örneğin yetersiz RAM/CPU veya port çakışması olan) node'ları eler.
    2.  **Scoring (Priorities / Puanlama):** Filtrelemeden kalan node'lar arasında bir puanlama yapar. En yüksek puanı alan (örneğin en az yüklü olan veya en hızlı diske sahip) node seçilir.
* Karar verirken affinity/anti-affinity kurallarını, taint/toleration'ları, kaynak sınırlarını ve node doluluk oranlarını dinamik olarak hesaplar.

---

### kube-controller-manager

* **Kontrol Döngüleri:** Cluster içindeki çeşitli kontrolörleri (reconciliation loops) tek bir işletim süreci (process) içinde çalıştırır. Fiziksel dünyadaki bir klima termostatı gibidir; sürekli olarak odanın mevcut sıcaklığını (current state) ölçer ve ayarladığınız hedef dereceye (desired state) getirmek için ısıtıcıyı veya soğutucuyu devreye sokar.
* **"Desired State" (Beklenen Durum) vs "Current State" (Mevcut Durum):** Controller'ın yegane görevi, cluster'ın durumunu sürekli izleyip beklenen duruma (YAML dosyalarında belirttiğimiz) çekmektir.
* **Temel Kontrolörler:**
    - **Node Controller:** Node'ların erişilebilirlik durumunu izler; bir node düşerse üzerindeki pod'ların başka bir yere taşınmasını (tahliye) organize eder.
    - **Replication Controller:** Belirtilen replika sayısını denetler; eksikse yeni pod başlatır, fazlaysa fazlalıkları kapatır.
    - **Endpoints Controller:** Service ve Pod nesnelerini ilişkilendirerek IP yönlendirmelerini (Endpoint) günceller.
    - **Namespace Controller:** Bir namespace silindiğinde içindeki tüm kaynakların temizlenmesini sağlar.

---

### cloud-controller-manager

* Bulut sağlayıcılara özgü operasyonları (Cloud Load Balancer oluşturma, disk ekleme/çıkarma, bulut üzerindeki node durumlarını izleme) yöneterek Kubernetes'in bulut servisleriyle tamamen entegre çalışmasını sağlar.

---

## Worker Node Bileşenleri

Worker Node'lar, Control Plane'in verdiği kararları fiilen uygulayan ve konteynerleri çalıştıran işçi makinelerdir.

---

### kubelet

* **Şantiye Şefi:** Her node üzerinde çalışan ve node'u doğrudan API Server'a bağlayan ajandır. Kubelet, genel merkezden (API Server) gelen talimatları harfiyen yerine getiren bir şantiye şefi gibidir.
* Pod'ların içindeki konteynerlerin sağlıklı çalışıp çalışmadığını kontrol eder, çöken veya yanıt vermeyen pod'ları yeniden başlatır.

---

### Container Runtime (Containerd)

* **Konteyner Motoru:** Pod'ların içindeki konteynerleri fiilen çalıştıran alt motordur. Şantiye şefinin (kubelet) talimatları doğrultusunda tuğlaları üst üste koyup duvarı ören (konteyneri ayağa kaldıran) işçilerdir.
* 2026 Standardı: `containerd` standardı benimsenmiştir (Docker artık doğrudan kullanılmaz). Kubelet ile CRI (Container Runtime Interface) protokolü üzerinden haberleşir.

---

### kube-proxy (2026'da Cilium ile Değiştirildi)

> [!WARNING]
> 2026 standartlarında `kube-proxy` **Cilium eBPF** ile tamamen değiştirilmektedir. Küme kurulumu esnasında `kubeadm init --skip-phases=addon/kube-proxy` komutu ile devredışı bırakılıp Cilium kurulur.

---

### Cilium (eBPF CNI - 2026 Standardı)

* **Akıllı Otoyol Ağı:** Linux çekirdeğinde (kernel space) çalışarak ağ yönetimini ve paket yönlendirmesini `iptables` gibi hantal yapılardan arındırıp çok daha yüksek verimle yönetir. Liman içindeki tüm trafiği organize eden, güvenliği denetleyen akıllı bir otoban sistemi gibidir.
* Network Policy, Load Balancing, Egress ve Service Mesh yeteneklerini tek bir çatı altında sunar.
* **Hubble** arayüzü (UI) sayesinde ağ trafiği canlı olarak izlenebilir ve görselleştirilebilir.

---

## Bileşen İletişim Diyagramı

```
kubectl / API Client
        │
        ▼
┌──────────────────┐
│   kube-apiserver │◄─── etcd (durumu okur/yazar)
└──────┬───────────┘
       │
   ┌───┐────────────────────────┐
   │                            │
   ▼                            ▼
kube-scheduler          kube-controller-manager
(Pod'u hangi Node?)     (ReplicaSet, Node vb. döngüler)
   │
   ▼ (API üzerinden)
kubelet (Worker Node'da)
   │
   ▼
containerd → Container (Pod)
```

---

## Namespace

Namespace, cluster kaynaklarını mantıksal olarak gruplandıran sanal duvarlardır. Varsayılan namespace'ler:

| Namespace | Amacı |
|:---|:---|
| `default` | Kullanıcı uygulamaları (başka bir namespace belirtilmezse buraya kurulur) |
| `kube-system` | Kubernetes'in kendi sistem bileşenleri (DNS, scheduler, proxy vb.) |
| `kube-public` | Herkese açık kaynaklar ve bazı cluster doğrulama bilgileri |
| `kube-node-lease` | Node'ların kalp atışlarını (heartbeat) izleyen lease nesneleri |

```bash
# Namespace listesi
kubectl get namespaces

# Belirli namespace'de çalışma
kubectl get pods -n kube-system

# Yeni namespace oluşturma
kubectl create namespace my-app
```

> [!TIP]
> Production ortamında her ekip veya bağımsız uygulama için ayrı bir namespace kullanın. `ResourceQuota` ve `LimitRange` ile her namespace'e kaynak sınırı atayarak sistem kaynaklarının adil paylaşımını garanti altına alabilirsiniz.

---

## Static Pods

Static pod'lar, API Server'dan bağımsız olarak doğrudan ilgili node üzerindeki **kubelet** tarafından yönetilen pod'lardır. Kubernetes'in kendi kontrol düzlemi bileşenleri (etcd, API Server, Scheduler, Controller Manager) bu şekilde çalıştırılır.

```
/etc/kubernetes/manifests/
├── etcd.yaml
├── kube-apiserver.yaml
├── kube-controller-manager.yaml
└── kube-scheduler.yaml
```

```bash
# Kubelet bu dizini izler — dosya eklenince pod otomatik başlar
ls /etc/kubernetes/manifests/

# Static pod'lar kubectl'de mirror object olarak görünür
kubectl get pods -n kube-system
# kube-apiserver-master   1/1  Running  ← Static Pod!

# Silmek için manifest dosyasını kaldırmak gerekir (kubectl delete işe yaramaz)
sudo rm /etc/kubernetes/manifests/my-static-pod.yaml

# API Server çöktüğünde crictl ile debug et
sudo crictl ps -a
sudo crictl logs <container-id>
```

| Özellik | Static Pod | DaemonSet |
|---|---|---|
| **Yönetim** | Kubelet (doğrudan manifest izler) | API Server / DaemonSet Controller |
| **API Server Gerekli mi?** | ❌ Gerekli değildir | ✅ Gereklidir |
| **kubectl Yönetimi** | ❌ Sadece salt-okunur (mirror) | ✅ Tam CRUD desteği |
| **Kullanım Amacı** | Kontrol düzlemi bileşenleri (Bootstrapping) | Log/metrik toplama ajanları, ağ eklentileri |
