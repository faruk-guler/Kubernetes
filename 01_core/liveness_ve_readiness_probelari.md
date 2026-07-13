# Sağlık Kontrolleri ve Kesinti Bütçesi

Kubernetes, bir uygulamanın çöküp çökmediğini anlamak için varsayılan olarak çok basit bir mantık kullanır: *"Eğer pod içindeki process (uygulama kodu) durduysa (exit 1), pod çökmüştür, yenisini açayım. Eğer process çalışıyorsa, pod sağlıklıdır."*

Ancak gerçek dünya bu kadar basit değildir. Java uygulamanız çalışıyor (process aktif) olabilir ama bir *Deadlock (kilitlenme)* yaşandığı için kullanıcılara cevap veremiyordur. Veya uygulamanız çok büyüktür ve çalışmaya başlaması (önbelleği doldurması) 2 dakika sürüyordur; henüz hazır olmadığı halde Kubernetes ona hemen internet trafiği gönderirse kullanıcılar hata alır.

İşte uygulamanızın **gerçekten** ne durumda olduğunu Kubernetes'e söylemenin yolu **Probe (Sonda/Sensör)** mekanizmalarından geçer.

---

## 1. Sağlık Kontrolleri (Probes)

Üç farklı probe (sensör) türü vardır ve Kubernetes ortamında güvenilir bir sistem kurmak için bunların en az ikisi (Liveness ve Readiness) mutlaka kullanılmalıdır.

### A. Liveness Probe (Yaşam Sensörü)

**Amaç:** Uygulama kilitlendi mi? Kendi kendine kurtulamayacak bir hataya mı düştü?
**Aksiyon:** Eğer bu probe başarısız olursa, Kubernetes pod'u acımasızca "öldürür" (restart eder) ve temiz bir sayfa açar.
*Örnek Kullanım:* Uygulamanın `/healthz` adresine saniyede bir HTTP isteği atmak.

### B. Readiness Probe (Hazırlık Sensörü)

**Amaç:** Uygulama şu an internetten veya diğer servislerden trafik almaya (kullanıcılara hizmet vermeye) hazır mı?
**Aksiyon:** Eğer bu probe başarısız olursa, Kubernetes pod'u **ÖLDÜRMEZ**. Ancak o pod'u yük dengeleyicinin (Service) arkasından çıkarır; yani o pod düzelene kadar ona müşteri trafiği yollamaz.
*Örnek Kullanım:* Uygulamanın veritabanına başarılı şekilde bağlanıp bağlanmadığını test etmek. Bağlantı kopuksa trafik alma, bağlanınca trafiği tekrar aç.

### C. Startup Probe (Başlangıç Sensörü)

**Amaç:** Uygulama henüz ilk açılışını (boot) tamamladı mı?
**Aksiyon:** Özellikle eski, monolitik ve yavaş açılan (örneğin 3 dakikada açılan) Java uygulamaları için kullanılır. Startup Probe başarılı olana kadar, Liveness ve Readiness sensörleri bekletilir. Böylece uygulamanız sırf geç açılıyor diye Liveness Probe tarafından "kilitlendi" sanılıp sonsuz bir restart döngüsüne sokulmamış olur.

> **Nasıl Kontrol Edilir?**
> Sensörler 4 farklı yolla uygulamanızı test edebilir:
>
> 1. **httpGet:** `/health` adresine HTTP isteği atarak 200 kodunu bekler.
> 2. **tcpSocket:** Belirli bir porta (Örn: MySQL için 3306) bağlanmayı dener.
> 3. **exec:** Pod içine girip bir komut (Örn: `cat /tmp/ready`) çalıştırır.
> 4. **grpc:** gRPC protokolü üzerinden sağlık testi yapar.

---

## 2. Düzgün Kapanma (Graceful Shutdown)

Bir pod silineceği zaman Kubernetes fişi aniden çekmez.

1. Önce pod'a `SIGTERM` (Lütfen Kapan) sinyali gönderir.
2. Ardından uygulamanızın yarım kalan işlerini bitirmesi, açık veritabanı bağlantılarını kapatması için **30 saniye** bekler (`terminationGracePeriodSeconds`).
3. 30 saniye dolduğunda uygulama hala inatla kapanmamışsa, bu kez `SIGKILL` ile acımasızca zorla kapatır.

Eğer uygulamanız kapanmadan önce özel bir işlem yapması gerekiyorsa `preStop` (kapanma öncesi) kancasını kullanabilirsiniz (Örneğin, kapanmadan önce yük dengeleyiciden çıkmayı beklemek). Uzun süren işler yapan podlarınız varsa (video işleme), bu 30 saniyelik süreyi manifest dosyasında artırmanız zorunludur.

---

## 3. Pod Kesintisi Bütçesi (Pod Disruption Budget - PDB)

Kendi kendinize çok güvenli, 5 kopyalı (replica) bir Deployment kurdunuz, Liveness ve Readiness Probelarını mükemmel ayarladınız. Ancak bir gün Sistem Yöneticisi (Ops ekibi) sunuculardan (node) birini bakım için tahliye etmeye karar verdi (`kubectl drain node-1`).

Eğer 5 kopyanızın tümü tesadüfen o sunucudaysa ve sistem yöneticisi o node'u kapatırsa, **%100 Servis Kesintisi (Downtime)** yaşarsınız!

İşte bu tür *planlı kesintilere* karşı uygulamanızı koruyan zırhın adı **Pod Disruption Budget (PDB)**'dir.

**PDB Nasıl Çalışır?**
Kubernetes'e açıkça şu emri verirsiniz: *"Şirkette yangın bile çıksa, sunucular bakıma bile alınsa, benim bu uygulamamın aynı anda en az 3 kopyası AYAKTA KALMAK ZORUNDADIR (`minAvailable: 3`)."*

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [liveness_ve_readiness_probelari_manifest_1.yaml](../Manifests/01_core/liveness_ve_readiness_probelari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu kuralı koyduğunuzda, sistem yöneticisi o node'u bakıma almak için tahliye komutu (`drain`) verse bile, Kubernetes o sunucuyu kapatmayı **REDDEDER**. Önce silinen pod'ların diğer sunucularda ayağa kalkmasını bekler, sayı tekrar 3'ün üzerine çıktığında tahliye işlemine devam etmeye izin verir. PDB, production ortamlarının tartışılmaz güvenlik kilitlerinden biridir.

---

Bölüm 2'yi başarıyla tamamladık. Şu ana kadar hep uygulamalarımızı nasıl çalıştırıp yaşatacağımızı konuştuk. Ancak bu pod'lar dış dünyayla ve birbirleriyle nasıl iletişim kuracak? İnternetten sitemize giren bir müşteri, arka plandaki pod'lara nasıl ulaşacak?

Tüm bu soruların cevabı için bir sonraki bölüm olan **Bölüm 3: Ağ (Networking) ve Servis Keşfi** kısmına geçiyoruz.
