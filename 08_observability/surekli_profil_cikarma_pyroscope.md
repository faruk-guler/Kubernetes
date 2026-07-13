# Sürekli Profil Çıkarma (Continuous Profiling) ve eBPF Devrimi

Yıllar boyunca Gözlemlenebilirlik (Observability) "Kutsal Üçlü" (Three Pillars) üzerine inşa edildi:

1. **Metrikler:** "Sistem yavaşladı mı?" (Örn: Prometheus)
2. **Loglar:** "Servis neden hata verdi?" (Örn: Loki)
3. **İzleme (Tracing):** "İstek hangi serviste tıkandı?" (Örn: Tempo)

Fakat 2026 standartlarında bu üçlü, karmaşık sistemlerde yetersiz kalmaktadır. Eğer sistem loga hata basmıyorsa, sadece CPU %100'de kilitleniyorsa, sorunun hangi serviste olduğunu Tracing ile bulabilirsiniz. Ancak o servisin içindeki **hangi fonksiyonun**, **hangi satırının** bu işlemciyi yorduğunu nasıl bulacaksınız?

İşte Gözlemlenebilirliğin 4. Sütunu burada devreye giriyor: **Sürekli Profil Çıkarma (Continuous Profiling)**.

---

## 1. Profiling Neden Eskiden Zordu?

Profil çıkarma (hangi kod satırının ne kadar CPU/Bellek yaktığını analiz etme) işlemi aslında yenilik değildir. Yazılımcılar pprof (Go) veya JFR (Java) gibi araçlarla bunu yıllardır yapıyor.

Ancak eskiden bu işlem ciddi bir **ek yük (overhead)** yaratırdı. Canlı (production) bir Kubernetes kümesinde profil almayı açarsanız, CPU ölçümünün kendisi CPU yediği için sistem daha da yavaşlardı. Bu yüzden sadece test ortamlarında veya lokalde yapılırdı.

## 2. Oyun Değiştirici: eBPF (Extended Berkeley Packet Filter)

**eBPF**, kodu değiştirmeden Linux Çekirdeği (Kernel) seviyesinde ölçüm yapmayı sağlayan devrimsel bir teknolojidir.

Grafana Pyroscope veya Parca gibi modern araçlar, eBPF kullanarak podlarınızın içine "kod enjekte etmeden" (Zero-Instrumentation) tüm fonksiyonların CPU ve RAM haritalarını çıkarır. Sistem üzerindeki performans yükü **%1'den bile azdır**. Bu sayede 7/24, canlı ortamda, tüm cluster'ın profilini çıkarabilirsiniz.

---

## 3. CNCF Profiling Araçları

Günümüzde bu alanda iki dev öne çıkmaktadır:

### A. Grafana Pyroscope

Açık kaynaklı Phlare projesiyle birleşerek devasa bir güce ulaşan Pyroscope, Go, Python, Java, Node.js ve Rust dahil pek çok dili doğrudan eBPF ile profiller. Grafana arayüzüne entegre gelir, yani Prometheus metriklerinde bir zıplama gördüğünüz an, tek tıklamayla o anki Profil grafiğine geçiş yapabilirsiniz.

### B. Parca

PolarSignals tarafından geliştirilmiş, tamamen eBPF odaklı ve son derece modern bir profil aracıdır. En büyük avantajı, kodunuzda hiçbir değişiklik yapmadan sadece DaemonSet olarak kümenize kurduğunuz an çalışmaya başlamasıdır.

---

## 4. Pyroscope eBPF Kurulumu

Pyroscope'u tüm cluster'ı izleyecek şekilde (DaemonSet olarak) Helm ile kurarken eBPF özelliğini aktifleştirmek yeterlidir.

> 📌 **Örnek Kurulum:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [profiling_manifest_1.yaml](../Manifests/08_observability/profiling_manifest_1.yaml) adresinden inceleyebilirsiniz.

Bu yapılandırma ile yüklenen ajan, Kubernetes düğümündeki çekirdeğe (Kernel) yerleşir ve üzerinde koşan tüm konteynerlerin bellek sızıntılarını (memory leaks) saniye saniye kaydeder.

---

## 5. Alev Grafikleri (Flame Graphs) Nasıl Okunur?

Profil araçlarının size sunduğu görselleştirme modeline "Alev Grafiği" denir.

* **x-Ekseni (Yatay Genişlik):** Bir fonksiyonun ne kadar kaynak (CPU veya RAM) tükettiğini gösterir. Kutu ne kadar genişse, fonksiyon o kadar kaynak yiyordur.
* **y-Ekseni (Dikey Derinlik):** Fonksiyonların çağrı hiyerarşisini (Call Stack) gösterir. En üstteki kutu, altındakini çağırmıştır.

**Özetle:** Alev grafiğine baktığınızda, yatayda en geniş yer kaplayan kod bloğunu bulup optimize ederseniz, bulut faturanızdaki sunucu maliyetlerini anında yarı yarıya düşürebilirsiniz. FinOps ve Profiling 2026'nın ayrılmaz bir ikilisidir.
