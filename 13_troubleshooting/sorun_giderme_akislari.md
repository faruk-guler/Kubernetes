# Katmanlı Sorun Giderme Akışları (Troubleshooting Flows)

Kubernetes üzerinde bir hata ile karşılaşıldığında, rastgele komutlar çalıştırmak yerine sistematik bir hata teşhis (diagnostic) hiyerarşisi izlemek hata çözme süresini (MTTR) drastik şekilde kısaltır. Bu rehberde, en alt katmandan (Pod) en üst katmana (Control Plane) kadar adım adım sorun giderme akışları ele alınmıştır.

---

## 1. Hata Teşhis Hiyerarşisi

Herhangi bir sorun anında aşağıdaki sıralama ile katmanlar incelenmelidir:

```
[ HATA TEŞHİS ADIMLARI ]
        │
        ├──► 1. Pod Katmanı       ──► Pod çalışıyor mu? Günlükler (logs) ne diyor?
        │
        ├──► 2. Servis Katmanı    ──► Selector etiketleri uyuşuyor mu? Endpoint'ler dolu mu?
        │
        ├──► 3. Ağ (Network)      ──► DNS çözümlemesi yapılıyor mu? NetworkPolicy mi engelliyor?
        │
        ├──► 4. Düğüm (Node)      ──► Düğüm 'Ready' mi? Disk veya Bellek baskısı var mı?
        │
        └──► 5. Kontrol Düzlemi   ──► API Server, Scheduler ve etcd sağlıklı mı?
```

---

## 2. Pod Katmanı Hata ve Durum Rehberi

Pod durumlarının (status) anlamları ve ilk bakılması gereken yerler:

| Pod Durumu (Status) | Olası Anlamı | Hata Tespit / Kurtarma Adımı |
| :--- | :--- | :--- |
| `Pending` | Pod henüz zamanlanamadı (scheduled). | Düğüm kaynak yetersizliği veya `Taint/Toleration` uyumsuzluğu. `kubectl describe pod` -> Events bölümüne bakın. |
| `ImagePullBackOff` | Konteyner imajı indirilemedi. | İmaj adı/etiketi yanlış veya özel kayıt defteri (private registry) için `imagePullSecrets` eksik. |
| `CrashLoopBackOff` | Konteyner başlıyor ancak hemen çöküyor. | Uygulama içi kod hatası, eksik ortam değişkeni (env) veya veritabanı bağlantı hatası. `kubectl logs --previous` ile inceleyin. |
| `OOMKilled` | Konteyner bellek sınırını aştı. | Konteyner üzerinde tanımlanan `limits.memory` yetersizdir. Sınırı artırın. |
| `Evicted` | Düğümde kaynak bittiği için pod tahliye edildi. | Düğümün disk veya bellek durumunu (`df -h`, `free -m`) kontrol edin. |
| `Terminating` | Pod silinirken askıda kaldı. | Genellikle finalizer veya PV bağlantısının kopmamasından kaynaklanır. Zorla silmek için: `kubectl delete pod <pod-name> --grace-period=0 --force` |

### Pod Sorun Giderme Komutları

```bash
# 1. Pod detaylarını ve sistem olaylarını (Events) inceleme (İlk Bakılacak Yer!)
kubectl describe pod <pod-name> -n <namespace>

# 2. Çalışan podun canlı loglarını takip etme
kubectl logs <pod-name> -n <namespace> --tail=100 -f

# 3. CrashLoopBackOff durumunda bir önceki çöken container loglarını okuma
kubectl logs <pod-name> -n <namespace> --previous
```

---

## 3. Servis ve Endpoint Sorunları

Uygulamanız çalışıyor ancak dışarıdan veya diğer podlardan erişilemiyorsa:

```bash
# 1. Servise bağlı aktif podların IP adreslerini (endpoints) listeleyin
kubectl get endpoints <service-name> -n <namespace>
# Çıktı boş veya "<none>" ise -> Servis 'selector' etiketleri ile Pod etiketleri uyuşmuyor demektir!

# 2. Servis selector tanımını doğrulayın
kubectl get svc <service-name> -n <namespace> -o yaml | grep -A5 selector

# 3. Port-Forward ile doğrudan podu lokalde test edin
kubectl port-forward pod/<pod-name> 8080:8080 -n <namespace>
```

---

## 4. Ağ ve DNS Sorunları Teşhisi

Servislerin birbirleriyle isim kullanarak konuşamaması (DNS çözümlenmemesi) durumunda:

```bash
# 1. Teşhis için geçici bir DNS test podu başlatın
kubectl run dns-test --image=busybox:1.36 --restart=Never -it --rm -- sh

# 2. Pod içinden DNS testlerini koşturun
nslookup kubernetes.default                        # K8s Dahili API DNS kontrolü
nslookup <service-name>.<namespace>.svc.cluster.local # Servis DNS kontrolü
nslookup google.com                                # Dış dünya (Upstream) DNS kontrolü

# 3. CoreDNS podlarının durumunu denetleyin
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

---

## 5. Düğüm (Node) Sorunları Teşhisi

Düğümlerin `NotReady` durumuna düşmesi ve podların o düğüme zamanlanamaması:

```bash
# 1. Düğümlerin genel kaynak durumunu inceleyin
kubectl top nodes

# 2. Sorunlu düğümün koşul (conditions) durumunu sorgulayın
kubectl describe node <node-name> | grep -A10 "Conditions:"

# 3. Düğüm üzerindeki işletim sistemi kaynaklarını kontrol edin (SSH ile)
df -h          # Disk doluluğu (DiskPressure tetiklenmiş olabilir)
free -m        # Bellek durumu (MemoryPressure tetiklenmiş olabilir)
```

---

## 6. Acil Durum Hata Arama Çantası (Black Belt)

Hızlıca teşhis koymak için en popüler arama kalıpları:

```bash
# Küme genelinde çalışır durumda OLMAYAN tüm podları bulma
kubectl get pods -A | grep -v -E "Running|Completed"

# Son 30 dakika içindeki tüm Warning (Hata/Uyarı) olaylarını listeleme
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -30

# Belirli bir podun yaşam döngüsü boyunca aldığı tüm olayları listeleme
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name> --sort-by='.lastTimestamp'

# Kubelet servisindeki hata kayıtlarını çekme
journalctl -u kubelet --since "1 hour ago" -p err --no-pager
```

> [!TIP]
> Vakaların %80'inde sorun `kubectl describe pod` komutunun en altında yer alan **Events** bölümünde açıkça yazar. Bu bölümü okumadan sunucularda işlem yapmayın.
