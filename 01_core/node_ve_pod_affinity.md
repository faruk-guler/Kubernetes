# Gelişmiş Zamanlama (Scheduling)

Bir önceki bölümde pod'lara CPU ve RAM limitleri koymayı öğrendik. Kubernetes'in Scheduler (Zamanlayıcı) bileşeni, bir pod'u yerleştireceği zaman önce boş yeri olan sunucuları bulur. Eğer birden fazla uygun sunucu varsa, pod'u hangisine yerleştirmeli?

Veya daha spesifik senaryolar düşünelim:

- "Bu pod Yapay Zeka podu, bunu sadece üzerinde GPU bulunan sunuculara koy!"
- "Bu veritabanı podu çok kritik, onu sakın Frontend podlarıyla aynı sunucuya koyma!"
- "Bu sunucunun diski bozulmak üzere, hiçbir podu buraya gönderme!"

İşte bu tür senaryoları çözmek için Gelişmiş Zamanlama kurallarını kullanırız.

---

## 1. NodeSelector ve Affinity (Yakınlık) Kuralları

En temel kural, pod'un gideceği sunucuyu Etiketlere (Labels) göre seçmesidir.

**NodeSelector:** En eski ve basit yöntemdir. Pod'a `disktype: ssd` yazarsınız, Scheduler sadece üzerinde `disktype=ssd` etiketi olan sunucuları seçer. Ancak bu çok katı bir kuraldır, sunucu yoksa pod sonsuza kadar bekler (Pending).

Daha esnek, akıllı ve modern yöntem **Affinity (Yakınlık)** kurallarıdır.

### Node Affinity (Sunucu Yakınlığı)

Pod'un belirli özelliklere sahip sunuculara (Node) gitmesini sağlar.
İki türü vardır:

- **Zorunlu (Required):** "Bu pod kesinlikle GPU olan sunucuya gitmeli, yoksa çalışma!"
- **Tercih Edilen (Preferred):** "Mümkünse GPU olan sunucuya git, ama GPU sunucular doluysa beni normal bir sunucuya da koyabilirsin, sorun değil."

### Inter-Pod Affinity ve Anti-Affinity (Podlar Arası İlişkiler)

Pod'lar sunucu etiketlerine değil, **içeride çalışan diğer pod'lara** göre yer seçer.

- **Affinity (Çekim - Birlikte Çalış):** "Ben bir Web Sunucusu poduyum. Veritabanı ile çok hızlı konuşmam lazım. Beni her zaman Cache (Önbellek) podunun olduğu sunucuya yerleştir ki ağ gecikmesi olmasın."
- **Anti-Affinity (İtme - Uzak Dur):** "Biz 3 kopyalı bir veritabanıyız. Bizi sakın aynı sunucuya koyma! Eğer üçümüz de aynı sunucuya düşersek ve o sunucu yanarsa sistem çöker. Bizi fiziksel olarak farklı sunuculara (veya farklı veri merkezlerine) dağıt."

---

## 2. Topology Spread Constraints (Modern Dağıtım)

Pod Anti-Affinity kuralı pod'ları ayrı tutmakta çok başarılıdır, ancak çok sert bir "Ya hep ya hiç" (Binary) kuralıdır.

Büyük kümelerde, "Pod'ları sunuculara (veya bölgelere - zones) olabildiğince **eşit ve dengeli** dağıt" demek istiyorsak, 2026 Kubernetes dünyasının endüstri standardı **Topology Spread Constraints** kullanırız.

**Nasıl Çalışır?**
Örneğin AWS'te uygulamanız `eu-west-1a`, `eu-west-1b` ve `eu-west-1c` bölgelerinde çalışıyor. Elinizde 6 adet kopya (replica) var.
Eğer kural koymazsanız 4 tanesi `1a`'ya, 2 tanesi `1b`'ye düşebilir. `1a` bölgesinde elektrik kesilirse 4 kopyayı birden kaybedersiniz!
Topology Spread kullanarak *"Bölgeler arasındaki pod sayısı farkı en fazla 1 olabilir (maxSkew: 1)"* dersiniz. Scheduler podları `2-2-2` şeklinde kusursuz bir dengeyle bölgelere dağıtır.

---

## 3. Taints ve Tolerations (Lekeler ve Toleranslar)

Affinity kuralları pod'ların bir yere "gitmek istemesiyle" (Çekim) alakalıydı.
Taint (Leke) ise bunun tam tersidir: **Sunucunun podları kendinden uzaklaştırmasıdır (İtme).**

Diyelim ki elinizde sadece makine öğrenimi ekibi için ayrılmış, çok pahalı 2 adet GPU sunucusu var. Kümedeki normal web sunucularının tesadüfen bu pahalı sunuculara gelip kaynakları işgal etmesini istemezsiniz.

Bunun için o 2 sunucuya bir **Taint (Leke/Zehir)** sürersiniz:
`kubectl taint nodes gpu-node-1 ekip=yapay-zeka:NoSchedule`

Bu andan itibaren Scheduler, kümedeki HİÇBİR pod'u o sunucuya koymaz. Sunucu adeta karantinaya alınmış gibi diğer herkesten izole olur.

Peki yapay zeka ekibinin pod'ları bu sunucuya nasıl girecek?
Yapay zeka ekibi, kendi pod manifestosuna bir **Toleration (Panzehir/Tolerans)** yazar: *"Benim `ekip=yapay-zeka` lekesine karşı toleransım var, bu leke beni etkilemez."*
İşte sadece bu panzehire sahip pod'lar o sunucuya girebilir.

> **Bakım Çalışması (Node Drain)**
> Sistem yöneticisi bir sunucuyu işletim sistemi güncellemesi için bakıma almak istediğinde `kubectl drain node-1` komutunu çalıştırır. Kubernetes arka planda o sunucuya `NoExecute` adlı çok agresif bir Taint sürer. Bu taint sadece yeni pod'ların gelmesini engellemekle kalmaz, içeride çalışmakta olan toleranssız mevcut podları da **tahliye edip** başka sunuculara kaçırır.

---

## 4. Pod Priority ve Preemption (Öncelik ve Tahliye)

Peki ya kümenizdeki 10 sunucunun tamamı %100 doluysa ve sistem yöneticisinin acil olarak o kümeye kritik bir bakım pod'u sokması gerekiyorsa ne olacak? Normalde Scheduler "Yer yok" der ve yeni pod'u `Pending` (Beklemede) durumunda bırakır.

Bunu aşmak için **PriorityClass (Öncelik Sınıfları)** kullanılır.
Örneğin 0'dan 1.000.000'a kadar öncelik puanları belirlersiniz.

- Normal Pod'lar: 1000 Puan
- Kritik Ödeme Sistemi Pod'ları: 100.000 Puan

Eğer sunucular tam doluysa ve 100.000 puanlık kritik bir pod gelirse, Scheduler sunuculardaki 1000 puanlık zavallı podlardan birkaçını **tahliye eder (öldürür)**. Onların boşalttığı yere (Preemption - Gasp etme) bu yüksek öncelikli elit pod'u yerleştirir. Bu mekanizma sistemin asla kilitlenmemesini sağlar.

Zamanlama (Scheduling) işlemlerini mükemmel bir şekilde ayarladığımıza göre, artık kümemizin sınırlarını korumak, sadece yetkili kişilerin (veya diğer pod'ların) işlem yapmasını sağlamak için Kubernetes'in en kritik konusuna geçiyoruz.

Sıradaki bölüm: **Bölüm 6: Güvenlik (Security) ve Erişim Yönetimi.**
