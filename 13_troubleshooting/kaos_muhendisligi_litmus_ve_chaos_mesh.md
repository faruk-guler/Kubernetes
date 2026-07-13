# Kaos Mühendisliği (Chaos Engineering): Litmus ve Chaos Mesh

Mikroservisler ve dağıtık Kubernetes sistemleri inanılmaz derecede karmaşıktır. Ne kadar iyi test yazarsanız yazın, üretim (production) ortamında beklenmedik donanım arızaları, ağ kopmaları veya bağımlılık çökmeleri yaşanması kaçınılmazdır.

**Kaos Mühendisliği**, "Sistem çöktüğünde ne olacak?" sorusuna gece saat 03:00'te uykudan uyanarak cevap aramak yerine, sistem daha sağlıklıyken ve herkes ofisteyken **kasıtlı olarak arızalar çıkararak** sistemin dayanıklılığını (resilience) test etme pratiğidir. İlk kez Netflix'in "Chaos Monkey" projesiyle popülerleşmiştir.

---

## 1. Kaos Mühendisliği İlkeleri

1. **Hipotez Kurma:** Önce sistemin normal davranışını (Steady State) tanımlayın. Örnek hipotez: *"Payment-Service pod'larından biri ölürse, sistem hata vermeden yeni pod gelene kadar çalışmaya devam eder."*
2. **Patlama Yarıçapı (Blast Radius):** Teste çok küçük bir çapta başlayın. Önce geliştirme ortamında bir pod'u öldürün. Başarılıysa kapsamı genişleterek canlı ortamda koca bir sunucuyu (Node) kapatın.
3. **Otomasyon:** Sürekli Entegrasyon (CI/CD) boru hatlarında kaos testlerini otomatik hale getirin.

---

## 2. CNCF Araçları: Litmus vs Chaos Mesh

Günümüzde (2026 standartlarında) Kubernetes üzerinde rastgele pod silen basit komut dosyaları (script) yerine, CNCF ekosistemindeki profesyonel "Kaos Operatörleri" kullanılır. Pazarda iki dev araç öne çıkmaktadır:

### A. Chaos Mesh

* **Mimari:** PingCAP tarafından geliştirilmiş, eBPF ve DaemonSet'ler üzerinden çalışan inanılmaz güçlü bir ağ ve çekirdek (kernel) manipülasyon aracıdır.
* **Yetkinlik:** Sadece pod'ları öldürmekle kalmaz; CPU sıcaklığını sanal olarak artırabilir, belleği yavaşlatabilir, disk okuma hızına gecikme ekleyebilir ve DNS sorgularını bozabilir.
* **Kullanım Senaryosu:** Çok karmaşık ağ gecikmeleri ve donanım darboğazlarını test etmek isteyen ileri düzey platform mühendisleri için idealdir.

### B. LitmusChaos

* **Mimari:** ChaosMesh'e göre daha "iş akışı" (workflow) odaklıdır. ArgoCD ve Argo Workflows ile entegre çalışır.
* **Yetkinlik:** Bir ChaosHub (Uygulama Mağazası) sunar. Hazır deney senaryolarını (örneğin "Kafka broker node'unu düşür ve iyileşmeyi ölç") indirip anında çalıştırabilirsiniz.
* **Kullanım Senaryosu:** CI/CD hatlarına ve GitOps süreçlerine entegre, raporlama ve skorlama bekleyen SRE ekipleri için daha pratiktir.

---

## 3. Örnek Bir Kaos Deneyi (Chaos Mesh)

Bir mikroservise anlık ağ gecikmesi (Latency) ekleyerek, bu gecikmenin diğer servislerde bir "Timeout" felaketine yol açıp açmadığını test etmek en yaygın Kaos deneyidir.

Aşağıdaki deney, `payment-service` etiketli Pod'lara 1 dakika boyunca **200ms'lik bir ağ gecikmesi** enjekte eder. Deney bittiğinde her şey normale döner.

> 📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kaos_muhendisligi_manifest_1.yaml](../Manifests/13_troubleshooting/kaos_muhendisligi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu YAML'ı Kubernetes kümenize `kubectl apply` ile uyguladığınız anda, eBPF kuralları devreye girer ve ilgili pod'un ağ paketlerini kasıtlı olarak bekletmeye başlar.

---

## Özet

Kaos Mühendisliği, sistemi kırmak (break) için değil, **sistemin güvenilirliğini (reliability) kanıtlamak için** yapılır. Kubernetes'in *kendi kendini iyileştirme (self-healing)* özelliklerinin gerçekten çalışıp çalışmadığını görmenin tek yolu, sistem daha sağlıklıyken fişi çekme cesaretini göstermektir.
