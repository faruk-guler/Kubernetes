# Otomatik Ölçekleme (Autoscaling)

Kubernetes'in en çok övülen yeteneklerinden biri, trafiğin aniden artması durumunda (Örneğin Black Friday indirimleri veya ani bir TV reklamı) sistemin kendi kendini büyütebilmesi (Ölçeklenmesi) ve trafik azaldığında ise faturayı düşürmek için kendi kendini küçültebilmesidir.

Ancak ölçekleme tek bir sihirli değnek değildir, üç farklı boyutta gerçekleşir:

1. **HPA (Horizontal Pod Autoscaler):** Pod sayısını artırır.
2. **VPA (Vertical Pod Autoscaler):** Pod'un donanımını (CPU/RAM) büyütür.
3. **Cluster Autoscaler (veya Karpenter):** Podlar sunuculara sığmadığında, Bulut sağlayıcısından yeni sunucu (Node) kiralar.

Tüm bu sistemlerin çalışabilmesi için kümenizde `Metrics Server` bileşeninin kurulu olması zorunludur. Çünkü Kubernetes, "Trafik var mı?" sorusunu Metrics Server'a bakarak anlar.

---

## 1. HPA (Yatay Ölçekleme)

Bir web siteniz var ve `3` pod ile çalışıyor. Black Friday başladı ve kullanıcılar sitenize akın etti. CPU kullanımı %90'a dayandı.

**HPA** devreye girer. HPA'yı tanımlarken dersiniz ki: *"Eğer podların ortalama CPU kullanımı %70'i geçerse, bana yeni podlar oluştur. En fazla 20 poda kadar çıkabilirsin."*

```bash
# Terminalden tek satırla HPA oluşturmak:
kubectl autoscale deployment web-sitesi --cpu-percent=70 --min=3 --max=20
```

HPA, CPU %70'i geçtiğinde 4., 5. ve 6. podu açar. Trafik tüm podlara dağılır, ortalama CPU %40'lara düşer. Sistem rahatlar. Gece saat 03:00 olup herkes uyuduğunda, CPU %10'lara iner. HPA bu sefer tasarruf için podları teker teker siler ve tekrar 3 poda düşürür.

> [!WARNING]
> HPA'nın doğru çalışabilmesi için podlarınızın `resources.requests` (Bölüm 5) değerlerinin kesinlikle tanımlanmış olması gerekir! Kubernetes "Yüzde" hesaplamasını bu değere göre yapar.

### KEDA: Gelişmiş HPA

CPU veya RAM her zaman doğru gösterge değildir. Bazen arka planda çalışan bir uygulamanız vardır (Worker) ve sadece Kafka veya RabbitMQ'daki mesaj sayısına göre çalışması gerekir.
İşte burada **KEDA** (Kubernetes Event-Driven Autoscaling) devreye girer. KEDA, HPA'yı süper güçlerle donatır. *"RabbitMQ'da 1000'den fazla bekleyen mesaj varsa 50 pod aç, hiç mesaj yoksa **sıfır (0)** poda düş"* diyebilirsiniz.

---

## 2. VPA (Dikey Ölçekleme)

Bazen sorunun çözümü daha fazla pod eklemek (HPA) değildir. Özellikle eski nesil (Monolitik) uygulamalar veya veritabanları birden fazla kopyayla (Replika) çalışmayı sevmezler. Tek bir kopya olmak isterler ama çok fazla RAM ve CPU isterler.

Bu durumda **VPA** kullanılır. VPA, pod'un sayısını artırmaz; mevcut pod'un içine girip onun RAM limitini 2GB'dan 4GB'a, CPU'sunu 1'den 2'ye çıkarır.
Ancak VPA bu işlemi yaparken (şimdilik) pod'u kısa süreliğine yeniden başlatmak zorundadır.

> [!IMPORTANT]
> **Kritik Kural:** Aynı uygulama üzerinde hem HPA hem de VPA'yı (Aynı metrik için, örneğin CPU) aynı anda **KULLANMAYIN**. HPA CPU'yu düşürmek için pod sayısını artırmaya çalışırken, VPA CPU limitini artırmaya çalışır. İkisi kavga eder ve sistem dengesizleşir.

---

## 3. Cluster Autoscaler ve Karpenter (Sunucu Ölçekleme)

HPA harika çalıştı ve pod sayısını 3'ten 20'ye çıkardı diyelim. Peki ya bu 20 pod, sizin fiziksel veya sanal sunucularınızın kapasitesini (RAM'ini) aşarsa ne olacak?
HPA yeni podları oluşturur ancak Kubernetes bu podları koyacak yer bulamaz. Podlar **Pending (Beklemede)** durumuna geçer.

İşte tam bu noktada **Sunucu Ölçekleme** devreye girer. Geleneksel sistemlerde bu işi `Cluster Autoscaler` yapardı. Ancak 2026 yılı itibariyle sektör standardı **Karpenter** olmuştur.

### Neden Karpenter?

AWS tarafından geliştirilen ve açık kaynak olan Karpenter, inanılmaz derecede hızlı ve zekidir:

1. **Hız:** Geleneksel Autoscaler bir sunucuyu ayağa kaldırmak için 3-5 dakika bekletirken, Karpenter bulut sağlayıcısıyla (AWS, Azure vb.) doğrudan konuşur ve sunucuyu **30-60 saniye** içinde ayağa kaldırıp podları içine koyar.
2. **Ekonomi (FinOps):** Karpenter, bekleyen podların tam olarak ne kadar CPU ve RAM istediğini hesaplar. *"Şu an 10 pod bekliyor, bana tam onlara yetecek kadar, en ucuz fiyatlı (Spot) c5.xlarge sunucusundan getir"* der.
3. **Konsolidasyon (Birleştirme):** Gece olup trafik azaldığında ve sunucular boşalmaya başladığında Karpenter şunu fark eder: *"2 farklı sunucum var, ikisi de %30 dolu. Ben bu podları tek bir sunucuda birleştireyim, diğer sunucuyu tamamen kapatayım."* Bu sayede bulut faturalarınızı inanılmaz derecede düşürür.

Ölçeklemeyi hallettik ve trafiğimiz büyüdü. Peki binlerce mikroservisin birbiriyle güvenli ve akıllı bir şekilde nasıl iletişim kuracağını nasıl yöneteceğiz?
Cevap bir sonraki bölümde: **Service Mesh (İletişim Ağı) ve Istio.**
