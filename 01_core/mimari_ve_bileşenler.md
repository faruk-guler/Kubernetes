# Kubernetes Mimarisi (Derinlemesine)

Kubernetes kümesi (cluster), temelde iki ana parçadan oluşur: Orkestrayı yöneten beyin takımı (**Control Plane**) ve ağır işi yapan işçiler (**Worker Nodes**).

Bu bölümde sistemin genel mimarisini incelerken, aynı zamanda arka planda işlerin nasıl yürüdüğüne (API Priority, Container Runtime süreçleri) dair ileri seviye (Production) detaylara da gireceğiz.

---

## 1. Control Plane (Kontrol Düzlemi) Bileşenleri

Control Plane, Kubernetes'in beynidir. Sistemle ilgili küresel kararları (örneğin bir pod'un hangi sunucuda çalışacağını) alır ve sistem durumunu yönetir. Üretim (production) ortamlarında kesinti yaşanmaması için genellikle en az 3 adet sunucuya (High Availability) yayılır.

### A. API Server (kube-apiserver)

Kubernetes'in dış dünyayla ve kendi içindeki diğer bileşenlerle konuştuğu tek kapıdır. `kubectl` ile yazdığınız her komut veya arka planda çalışan her bir Kubernetes ajanı, sadece API Server ile iletişim kurar.

> **İleri Seviye Bilgi: API Priority and Fairness (APF)**
> Devasa cluster'larda API Server binlerce istekle boğulabilir. Hatalı bir araç API'yi çökertebilir. Kubernetes APF mekanizmasıyla bu sorunu çözer. İstekleri kuyruklara böler. Örneğin kritik sistem bileşenleri (kubelet vb.) asla bloke edilmezken, standart kullanıcı istekleri (`kubectl get pods`) sıraya alınabilir.

### B. etcd

Tüm cluster'ın "hafızasıdır". Kümedeki her bir objenin o anki durumu, konfigürasyonları ve şifreleri (secrets) burada saklanır. Dağıtık, tutarlı ve yüksek erişilebilir bir key-value (anahtar-değer) veritabanıdır.
*Üretim ortamlarında etcd disklerinin süper hızlı (NVMe SSD) olması, cluster performansını doğrudan etkiler.*

### C. Scheduler (kube-scheduler)

Yeni oluşturulan, ancak henüz bir sunucuya atanmamış (Pending) Pod'ları takip eder. Sunucuların bellek/CPU durumuna, kurallara (Affinity, Taints) bakarak pod'u çalıştırmak için **en uygun sunucuyu (node) seçer**.

### D. Controller Manager (kube-controller-manager)

Sistemin "istenen durumunu" (desired state) sürekli olarak kontrol eden döngülerdir (Control loops). Örneğin; "3 kopya çalışsın" dediyseniz ve sunuculardan biri çökerse, ReplicaSet Controller bunu fark eder ve API Server'a eksilen 1 kopyayı yeniden oluşturmasını söyler.

---

## 2. Worker Node (Veri Düzlemi) Bileşenleri

Konteynerlerin fiilen çalıştığı, CPU ve belleğin harcandığı işçi sunuculara Worker Node denir.

### A. Kubelet

Her node'da çalışan Kubernetes'in "kaptan" ajanıdır. API Server'dan gelen talimatları dinler. Bir pod'un başlatılması gerektiğinde, node içindeki Container Runtime'a talimat verir. Pod'ların sağlıklı çalışıp çalışmadığını (Health Checks) denetleyip Control Plane'e raporlar.

### B. Kube-proxy

Node üzerindeki ağ kurallarını yönetir. İçerideki servislerin (Service) birbirleriyle iletişim kurmasını ve trafiğin doğru pod'lara yönlendirilmesini sağlayan (genellikle iptables/IPVS kullanarak) ağ bileşenidir.

### C. Container Runtime (Konteyner Çalışma Zamanı)

Konteynerleri fiilen başlatan ve durduran yazılımdır. Kubelet ile iletişim kurmak için **CRI (Container Runtime Interface)** standardını kullanırlar.

* **Eski Dönem (Docker):** Eskiden Kubernetes doğrudan Docker'ı kullanırdı. Ancak Docker, Kubernetes için gereksiz olan birçok geliştirici aracını barındırıyordu ve CRI standardına doğrudan uymuyordu. Bu yüzden Kubernetes, 1.24 sürümü ile Docker desteğini (dockershim) sonlandırdı.
* **containerd:** Docker'ın içinden çıkarılarak sadeleştirilen, bugün bulut sağlayıcılarında (EKS, GKE, AKS) en yaygın kullanılan endüstri standardı CRI çalışma zamanıdır.
* **CRI-O:** Sadece ve sadece Kubernetes'in ihtiyaçlarını karşılamak üzere sıfırdan tasarlanmış, Red Hat (OpenShift) ekosisteminde varsayılan olan aşırı hafif ve güvenli bir alternatif çalışma zamanıdır.

> **İleri Seviye Bilgi: Node Üzerinde Sorun Giderme (crictl)**
> Kubernetes ortamlarında Docker yerine containerd kullanıldığı için, node'a SSH ile bağlandığınızda `docker ps` komutu çalışmaz. Bunun yerine Kubernetes'in resmi debug aracı olan `crictl` kullanılır:
>
> ```bash
> # Node üzerindeki tüm pod'ları listele
> crictl pods
> # Tüm containerları listele
> crictl ps
> # Bir containerın içine gir
> crictl exec -it <container-id> sh
> ```

---

## 3. Add-on'lar (Eklentiler)

Kubernetes tek başına tam bir sistem değildir, özelliklerini tamamlamak için bazı kritik eklentilere ihtiyaç duyar.

- **DNS (CoreDNS):** Pod'ların ve servislerin IP adreslerini ezberlememek için isim bazlı çözümleme yapar. Cluster içindeki iletişimin omurgasıdır.
- **CNI (Container Network Interface):** Kubernetes kendi başına pod'lara IP veremez. Bunun için Calico, Cilium, Flannel gibi Ağ Eklentileri (CNI) kurmanız gerekir.
- **Dashboard / Metrics:** Cluster'ı görsel olarak yönetmek ve kaynak tüketimini görmek için kurulan eklentilerdir (Örn: Metrics Server).

---

## Özet

Kubernetes, bir orkestrayı yönetmek için devasa bir kontrol düzlemine (API Server, etcd, Scheduler) ve işi fiilen yapan işçilere (Kubelet, Container Runtime) sahiptir.

Peki bu devasa mimariyi kendi bilgisayarımıza veya buluta nasıl kurarız? Bir sonraki bölümde kurulum ve ortam hazırlığına geçiyoruz.
