# Kubernetes Ağ Altyapısı Detayları (Networking Internals)

Kubernetes'te ağ iletişimi (networking), dağıtık sistemlerin en karmaşık ancak en kritik parçasıdır. Podların birbirini nasıl bulduğu, paketlerin fiziksel olarak hangi yollardan geçtiği ve kube-proxy/eBPF bileşenlerinin trafiği nasıl yönlendirdiği bu bölümde derinlemesine ele alınmıştır.

---

## 1. Temel Ağ Kuralları: Her Pod Benzersiz IP Alır

Kubernetes ağ modelinin en temel kuralı, her podun NAT (Network Address Translation) olmaksızın doğrudan erişilebilir benzersiz bir IP adresine sahip olmasıdır.

```
Node 1 (192.168.1.10):
  ├── Pod A: 10.244.1.2
  └── Pod B: 10.244.1.3

Node 2 (192.168.1.11):
  ├── Pod C: 10.244.2.2
  └── Pod D: 10.244.2.3

Kural: Pod A, Pod C ile doğrudan iletişim kurabilir (NAT yok).
       10.244.1.2 ──► 10.244.2.2 (İki IP de birbirini doğrudan görür)
```

Bu model, **CNI (Container Network Interface)** eklentileri (Cilium, Calico vb.) tarafından Linux kernel'indeki sanal ağ cihazları (`veth pair`, `bridge`, `overlay routing`) aracılığıyla sağlanır.

---

## 2. Paket Yolculuğu: Pod'dan Pod'a İletişim

### A. Aynı Düğüm (Node) Üzerindeki İletişim

Pod A, aynı düğüm üzerindeki Pod B'ye paket gönderdiğinde trafik fiziksel ağ kartına çıkmadan işletim sistemi çekirdeğindeki sanal köprü (bridge) üzerinden akar:

1. Pod A paketi kendi `eth0` kartına gönderir.
2. Bu kart, host üzerindeki sanal ağ kartına (`veth` pair) bağlıdır.
3. Paket host üzerindeki sanal köprüye (`cni0` veya `cbr0`) ulaşır.
4. Köprü, paketi Pod B'nin `veth` kartına, oradan da Pod B'nin `eth0` arayüzüne teslim eder.

```bash
# Linux bridge ve veth arayüzlerini listelemek için (Düğüm üzerinde):
ip link show type bridge
ip link show type veth
```

### B. Farklı Düğümler (Nodes) Arasındaki İletişim

Pod A (Node 1) farklı bir düğümdeki Pod C'ye (Node 2) paket gönderdiğinde:

1. Paket CNI köprüsü üzerinden düğümün yönlendirme tablosuna (route table) gönderilir.
2. Düğümün yönlendirme tablosunda, hedef pod subnet'ine (`10.244.2.0/24`) giden paketlerin Node 2 IP'sine (`192.168.1.11`) yönlendirileceği yazılıdır.
3. Paket, CNI türüne göre tünellenerek (VxLAN, Geneve veya doğrudan BGP yönlendirmesiyle) fiziksel ağ üzerinden Node 2'ye iletilir.
4. Node 2 paketi çözer (decapsulate) ve kendi köprüsü üzerinden hedef Pod C'ye ulaştırır.

```bash
# Düğüm üzerindeki yönlendirme tablosunu görüntülemek için:
ip route show
# Örnek Çıktı:
# 10.244.2.0/24 via 192.168.1.11 dev eth0 proto bird
```

---

## 3. kube-proxy ve Servis (Service) Trafiği

Kubernetes Service nesneleri sanal IP adreslerine (ClusterIP) sahiptir. Bu sanal IP'lerin gerçek pod IP'lerine dönüştürülmesi işini her düğümde koşan **kube-proxy** üstlenir.

### iptables Modu Çalışma Mantığı

Service oluşturulduğunda kube-proxy düğümlerdeki `iptables` kurallarını günceller:

1. Pod, Service IP'sine (`10.96.45.100:80`) istek atar.
2. Düğümün network stack'i paketi `iptables` PREROUTING zincirine sokar.
3. `KUBE-SERVICES` kuralları hedef IP'yi eşleştirir ve `KUBE-SVC-XXX` zincirine aktarır.
4. `iptables` istatistik modülü (statistic module) kullanarak rastgele bir hedef pod seçer (Round-Robin).
5. DNAT (Destination NAT) uygulanarak paket hedef podun IP'sine (`10.244.1.5:8080`) dönüştürülür.

```bash
# Düğüm üzerindeki Kubernetes iptables kurallarını incelemek için:
iptables -t nat -L KUBE-SERVICES | head -20
```

---

## 4. eBPF Modu (Cilium) — kube-proxy Olmadan İletişim

Modern Kubernetes altyapılarında `iptables` kurallarının getirdiği performans yükünü (CPU overhead) azaltmak için **Cilium eBPF** kullanılır. Bu modda `kube-proxy` devre dışı bırakılır:

```
[ Gelen Paket ] ──► [ Linux Kernel XDP / TC Hook ] ──► [ eBPF Programı ] ──► [ Doğrudan Pod IP ]
                                                             │
                                                  (DNAT Kernel Düzeyinde)
```

### Avantajları

* **Hız:** Paketler userspace'e veya hantal iptables kurallarına takılmadan doğrudan kernel düzeyinde (eBPF map lookup) DNAT edilir.
* **Ölçeklenebilirlik:** Binlerce servisin olduğu büyük kümelerde bağlantı hızı düşmez.

```bash
# Cilium eBPF servis eşlemelerini listelemek için:
cilium bpf lb list
```

---

## 5. DNS Çözümleme Zinciri

Pod içinden bir servis çağrıldığında DNS çözümleme süreci şu sırayla işler:

1. Pod içindeki uygulama `web-app.production.svc.cluster.local` adresine gitmek ister.
2. Pod içindeki `/etc/resolv.conf` dosyası sorgulanır ve DNS sunucusu olarak **CoreDNS ClusterIP**'si (`10.96.0.10`) hedef alınır.
3. Sorgu UDP/53 üzerinden CoreDNS podlarına iletilir.
4. CoreDNS, Kubernetes API Server ile konuşarak ilgili servisin ClusterIP'sini (`10.96.45.100`) döner.
5. Pod, bu ClusterIP'ye istek atar ve kernel düzeyindeki iptables/eBPF kuralları bunu pod IP'sine dönüştürür.

---

## 6. Ağ Teşhis Komutları (Troubleshooting Toolkit)

Ağ sorunlarını analiz ederken düğümlerde ve podlarda kullanabileceğiniz kritik komutlar:

```bash
# 1. Pod içinden DNS çözümleme kontrolü
nslookup web-app.production.svc.cluster.local

# 2. Port seviyesinde bağlantı testi (netcat)
nc -zv web-app.production 80

# 3. netshoot aracı ile canlı paket yakalama (tcpdump)
kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- bash
# (netshoot kabuğunda)
tcpdump -i any -n port 8080
```
