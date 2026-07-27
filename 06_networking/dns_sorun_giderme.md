# DNS Sorunlarını Giderme (DNS Troubleshooting)

Kubernetes kümelerinde (clusters) yaşanan ağ problemlerinin çok büyük bir kısmı DNS çözümleme (resolve) hatalarından kaynaklanır. Podlar küme içi servis isimlerine ulaşamayabilir, dış alan adlarına (external domains) bağlanırken zaman aşımı (timeout) alabilir veya DNS yanıtlarında yüksek gecikmeler yaşanabilir. Bu rehberde, DNS sorunlarını adım adım nasıl gidereceğinizi bulabilirsiniz.

---

## 1. Hızlı Teşhis Adımları

Sorun anında ilk kontrol edilmesi gereken komutlar:

```bash
# 1. CoreDNS podlarının durumunu ve hangi düğümlerde çalıştığını kontrol edin
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# 2. CoreDNS podlarının canlı günlüklerini (logs) takip edin
kubectl logs -n kube-system -l k8s-app=kube-dns -f --tail=50

# 3. CoreDNS ConfigMap yapılandırmasını inceleyin
kubectl get configmap coredns -n kube-system -o yaml
```

---

## 2. Debug Pod ile Çözümleme Testi

DNS çözümlemesini izole bir pod içinden test etmek için:

```bash
# 1. Teşhis araçlarını barındıran bir test podu başlatın
kubectl run dns-debug --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --restart=Never -it --rm -- bash

# 2. Pod içinde şu testleri koşturun:
nslookup kubernetes.default                        # Dahili API DNS testi
nslookup google.com                                # Dış dünya (Upstream) DNS testi
dig @10.96.0.10 billing-service.production.svc.cluster.local # Detaylı DNS sorgusu
```

---

## 3. Yaygın DNS Sorunları ve Çözümleri

### A. ndots Gecikmesi (Latency)

* **Belirti:** Dış domain sorguları (Örn: `api.stripe.com`) çok yavaş çözümlenir veya timeout alır.
* **Neden:** Pod içindeki `/etc/resolv.conf` dosyasında varsayılan olarak tanımlanan `ndots:5` ayarı yüzünden, nokta sayısı 5'ten az olan her adres için önce küme içi suffix'ler (`.cluster.local`, `.svc` vb.) taranır. Bu durum, her dış istek için 3-4 adet gereksiz DNS sorgusu üretir.
* **Çözüm:** Dış dünyaya yoğun sorgu atan podların DNS politikasını (`dnsConfig`) özelleştirerek `ndots` değerini düşürün:

    ```yaml
    spec:
      dnsConfig:
        options:
          - name: ndots
            value: "2"
    ```

### B. CoreDNS Podlarının CrashLoopBackOff Durumuna Düşmesi

* **Belirti:** CoreDNS podları sürekli yeniden başlar.
* **Neden 1:** Bellek yetersizliği (OOMKilled). Büyük kümelerde varsayılan bellek limiti (memory limit) yetersiz kalabilir.
* **Neden 2:** Loop eklentisi algılaması. Host makinedeki DNS döngüsü (loopback dns) CoreDNS içine aktarıldığında pod döngü hatası vererek çöker.
* **Çözüm:**
  * *OOMKilled için:* CoreDNS Deployment kaynağını düzenleyip bellek sınırlarını artırın (`limits.memory: 256Mi`).
  * *Loop hatası için:* Host üzerindeki `/etc/resolv.conf` dosyasında yer alan yerel döngü (loopback) DNS sunucu adreslerini (Örn: `127.0.0.53`) kaldırın ve gerçek DNS adreslerini girin.

### C. NetworkPolicy Kaynaklı DNS Engellemeleri

* **Belirti:** Podlar ne küme içini ne de küme dışını çözümleyebilir.
* **Neden:** Poda uygulanan NetworkPolicy kuralları, podun CoreDNS servisine (UDP/TCP port 53) giden trafiğini engellemektedir.
* **Çözüm:** NetworkPolicy içine DNS çıkış (Egress) iznini ekleyin:

    📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [dns_sorun_giderme_manifest_1.yaml](../Manifests/05_networking/dns_sorun_giderme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Teşhis Kontrol Listesi (Checklist)

```
□ CoreDNS podlarının durumu 'Running' mi?
□ CoreDNS loglarında 'Loop' veya 'OOM' uyarısı var mı?
□ Pod içindeki '/etc/resolv.conf' dosyası CoreDNS ClusterIP'sini (10.96.0.10) gösteriyor mu?
□ Ağ politikaları (NetworkPolicy) UDP port 53 çıkışına izin veriyor mu?
□ Düğümün (Node) kendi DNS sunucusu (Upstream DNS) sağlıklı çalışıyor mu?
```
