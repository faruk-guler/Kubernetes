# Ağ (Network) Sorunlarını Giderme

Kubernetes ağ sorunları genellikle karmaşık ve sinsi olabilir. Bir pod çalışıyor olmasına rağmen diğer podlara erişemeyebilir, servis üzerinden trafik geçmeyebilir veya DNS çözümleme işlemleri durabilir. Bu rehberde, ağ sorunlarını katman katman nasıl teşhis edeceğinizi bulabilirsiniz.

---

## 1. Ağ Teşhis Katmanları (Nereden Başlamalı?)

Sorunu daraltmak için yukarıdan aşağıya (Client -> Pod) doğru kontrol edin:

```
[ AĞ KATMANLARI ]
        │
        ├──► 1. Dış Dünya (LoadBalancer / Ingress)
        │
        ├──► 2. Yönlendirme (Service / Kube-Proxy / eBPF)
        │
        ├──► 3. Konteyner Düzeyi (Pod IP / Port)
        │
        └──► 4. Ağ Altyapısı (CNI - Cilium, Calico / Kernel iptables)
```

---

## 2. DNS ve Çözümleme Sorunları

Kubernetes içinde podlar servislerle isimleri üzerinden haberleşir. DNS çalışmadığında tüm iletişim durur.

```bash
# 1. Pod içinden DNS testi
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default

# 2. CoreDNS pod'larının durumunu denetleme
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 3. CoreDNS günlüklerini (logs) inceleme
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 4. Pod içindeki resolver yapılandırmasını kontrol etme
kubectl exec -it <pod-name> -n production -- cat /etc/resolv.conf
```

### Yaygın DNS Hataları

* **Farklı Namespace Erişimi:** Sadece `nslookup my-service` yazmak farklı namespace'deki servisi çözmez. Tam adresi (FQDN) kullanın: `my-service.<namespace>.svc.cluster.local`.
* **ndots Sorunu:** `/etc/resolv.conf` içindeki `ndots:5` ayarı nedeniyle kısa isim aramaları önce cluster içine sorulur ve dış dünya aramalarında yavaşlığa yol açabilir. Dış adreslerin sonuna nokta koyarak FQDN araması yapabilirsiniz: `google.com.`.

---

## 3. Servis (Service) ve Endpoint Erişim Sorunları

Eğer podunuz çalışıyor fakat servise gönderilen istekler ulaşmıyorsa:

```bash
# 1. Servisin durumunu kontrol edin
kubectl get svc -n production

# 2. Servisin arkasında canlı podlar var mı (endpoints) kontrol edin
kubectl get endpoints <service-name> -n production
# Çıktı boş veya "<none>" ise -> Servis etiket seçicisi (label selector) podlar ile eşleşmiyor demektir.

# 3. Servis port eşleşmelerini doğrulayın
kubectl describe svc <service-name> -n production
# 'Port' (servisin dışarı sunduğu port) ile 'TargetPort' (pod içindeki uygulamanın dinlediği port) eşleşmeli.

# 4. Podun gerçekten o portta dinleme yaptığını doğrulayın
kubectl exec -it <pod-name> -n production -- netstat -tlnp
```

---

## 4. Ingress ve Yönlendirme Hataları

Dışarıdan gelen HTTP/HTTPS istekleri uygulamaya ulaşmıyorsa:

```bash
# 1. Ingress Controller podunun durumunu ve loglarını kontrol edin
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# 2. Ingress kurallarını tanımlayan kaynağı denetleyin
kubectl describe ingress <ingress-name> -n production

# 3. Ingress Class tanımını doğrulayın
# (Eğer ingressClass yanlışsa controller bu ingress kuralını görmezden gelir)
kubectl get ingressclass
# YAML içindeki ingressClassName alanını kontrol edin
```

---

## 5. CNI ve NetworkPolicy Engellemeleri

Uygulamalar ve servisler doğru yapılandırılmış ancak paketler iletilemiyorsa sorun CNI (VxLAN tünel hataları vb.) veya NetworkPolicy kaynaklı olabilir.

```bash
# 1. Namespace içinde tanımlı ağ politikalarını listeleyin
kubectl get networkpolicy -n production

# 2. Hangi politikaların trafiği engellediğini denetleyin
kubectl describe networkpolicy <policy-name> -n production

# 3. Cilium CNI kullanılıyorsa ağ tünel durumunu test edin
cilium connectivity test
```

---

## 6. `netshoot` ile İleri Düzey Ağ Teşhisi

Ağ bant genişliği, gecikme ve paket kayıpları gibi durumlarda **nicolaka/netshoot** imajı kullanılır.

### Ağ Bant Genişliği Testi (`iperf3`)

CNI performansını veya sunucular arası ağ hızını ölçmek için:

```bash
# 1. Alıcı (Server) olarak bir netshoot podu başlatın
kubectl run netshoot-server --image=nicolaka/netshoot --rm -it --restart=Never -- iperf3 -s

# 2. Server pod IP'sini alıp Gönderici (Client) olarak testi başlatın
SERVER_IP=$(kubectl get pod netshoot-server -o jsonpath='{.status.podIP}')
kubectl run netshoot-client --image=nicolaka/netshoot --rm -it --restart=Never -- iperf3 -c $SERVER_IP
```

### Port ve İletişim Engeli Taraması (`nmap`)

Dış servislerin veya pod portlarının erişilebilirliğini test etmek için:

```bash
# Hedef servisin portlarını tarama (ping atmadan)
kubectl run netshoot-scanner --image=nicolaka/netshoot --rm -it --restart=Never -- \
  nmap -Pn -p 80,8080,3306 my-service.production.svc.cluster.local
```

---

## 7. Genel Ağ Teşhis Akış Şeması

```
[ AĞ BAĞLANTI SORUNU ]
        │
        ├──► 1. Pod çalışıyor mu? ──► Hayır ise? ──► Pod günlüklerine (logs) bak
        │
        ├──► 2. DNS çözülüyor mu? ──► Hayır ise? ──► CoreDNS durumunu / resolv.conf kontrol et
        │
        ├──► 3. Endpoint'ler dolu mu? ──► Hayır ise? ──► Servis etiket seçicisini (selector) düzelt
        │
        ├──► 4. Doğrudan Pod IP'sine ping gidiyor mu? ──► Hayır ise? ──► CNI / NetworkPolicy kontrol et
        │
        └──► 5. Servis IP'sine erişim var mı? ──► Hayır ise? ──► kube-proxy / eBPF kurallarını incele
```
