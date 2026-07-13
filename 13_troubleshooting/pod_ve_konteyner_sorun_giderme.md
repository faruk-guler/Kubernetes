# Pod ve Konteyner Sorunlarını Giderme

Kubernetes üzerinde karşılaşılan hataların çok büyük bir kısmı Pod katmanında meydana gelir. Bu rehberde, podların ve konteynerlerin en yaygın hata durumlarını (CrashLoopBackOff, OOMKilled, ImagePullBackOff, Pending ve Terminating) nedenleri ve çözüm yollarıyla birlikte inceleyebilirsiniz.

---

## 1. İlk Teşhis Adımları

Bir pod hata verdiğinde veya beklendiği gibi çalışmadığında çalıştırılması gereken ilk iki kritik komut:

```bash
# 1. Pod durumunu ve hangi düğümde çalıştığını sorgulama
kubectl get pod <pod-name> -n <namespace> -o wide

# 2. Pod detaylarını ve sistem olaylarını (Events) inceleme
kubectl describe pod <pod-name> -n <namespace>
```

`describe` çıktısında incelenmesi gereken kritik yerler:

* **Status / State:** Podun genel çalışma durumu ve hata kodu.
* **Last State:** Konteynerin bir önceki çöküş nedeni ve çıkış kodu (Exit Code).
* **Events:** Hatanın nedenini açıklayan gerçek zamanlı olay listesi (En altta yer alır).

---

## 2. CrashLoopBackOff Durumu

Konteynerin sürekli başlayıp ardından çökmesi ve Kubernetes'in her yeniden başlatma arasında bekleme süresini katlayarak artırması (Exponential Backoff) durumudur.

```bash
# 1. Konteynerin son çıkış kodunu (Exit Code) sorgulayın
kubectl describe pod <pod-name> | grep -A5 "Last State"

# 2. Bir önceki çöken konteynerin loglarını inceleyin
kubectl logs <pod-name> --previous

# 3. Pod içinde birden fazla konteyner varsa spesifik olanın logunu çekin
kubectl logs <pod-name> -c <container-name> --previous
```

### Kritik Çıkış Kodları (Exit Codes) ve Anlamları

* **Exit Code 1:** Uygulama içi kod hatası veya kural ihlali (Application Exception). Uygulama loglarını inceleyin.
* **Exit Code 137:** Konteyner **OOMKilled** (Out Of Memory) olmuştur; yani bellek limitini aştığı için işletim sistemi tarafından sonlandırılmıştır.
* **Exit Code 127:** Konteyner başlatma komutu bulunamamıştır (command/args hatalı).
* **Exit Code 126:** Komut dosyası çalıştırılamıyor (çalıştırma yetkisi eksik).

---

## 3. OOMKilled (Bellek Aşımı)

Konteyner, kendisi için tanımlanan `limits.memory` değerinden fazla bellek tüketmeye çalıştığında işletim sistemi tarafından sonlandırılır ve **137** çıkış koduyla çöküşe geçer.

```bash
# 1. Pod üzerindeki bellek durumunu ve OOM kaydını sorgulayın
kubectl describe pod <pod-name> | grep -E "OOMKilled|Exit Code"

# 2. Düğüm düzeyinde tetiklenen bellek baskısını sorgulayın
kubectl describe node <node-name> | grep -i "MemoryPressure"
```

### Çözüm Yolu

* Konteyner için tanımlanan `limits.memory` değerini artırın:

    ```yaml
    resources:
      requests:
        memory: "256Mi"
      limits:
        memory: "512Mi" # Bu limiti artırın
    ```

* Uygulamanızda bellek sızıntısı (memory leak) olup olmadığını geliştirme ekibiyle analiz edin.

---

## 4. ImagePullBackOff / ErrImagePull

Kubernetes'in konteyner imajını kayıt defterinden (Registry) indirememesi durumudur.

```bash
# Hata olaylarını inceleyin
kubectl describe pod <pod-name> | grep -A10 "Failed"
```

### Olası Nedenler ve Çözümleri

1. **Hatalı İmaj Adı veya Etiketi:** İmaj adı veya etiketinde (tag) yazım hatası yapılmıştır.
2. **Kimlik Doğrulama Hatası (Private Registry):** Özel bir kayıt defteri kullanılıyorsa, podun imajı çekebilmesi için gerekli olan `imagePullSecrets` tanımı eksik veya yanlıştır.

    ```bash
    # Secret oluşturun
    kubectl create secret docker-registry regcred \
      --docker-server=<registry-url> \
      --docker-username=<user> \
      --docker-password=<pass>
    ```

    ```yaml
    # Pod YAML dosyasına ekleyin
    spec:
      imagePullSecrets:
        - name: regcred
    ```

3. **Kayıt Defteri İstek Sınırı (Rate Limit):** Docker Hub gibi servislerde limitsiz indirme sınırı aşılmış olabilir.

---

## 5. Pending (Beklemede/Zamanlanamıyor)

Pod oluşturulmuştur ancak hiçbir Worker Düğüm (Node) üzerinde çalıştırılmak üzere zamanlanamamıştır (Scheduled).

### Olası Nedenler ve Teşhis

* **Kaynak Yetersizliği:** Düğümlerde podun `requests` değerlerini karşılayacak kadar CPU veya Bellek kalmamıştır.

    ```bash
    kubectl describe pod <pod-name> | grep -i "Insufficient"
    ```

* **NodeSelector / Affinity Kuralları:** Podun sadece belirli etiketlere sahip düğümlerde çalışması istenmiş ancak uygun etiketli düğüm bulunamamıştır.

    ```bash
    kubectl get nodes --show-labels
    ```

* **Taint / Toleration Engelleri:** Düğümler üzerinde podların zamanlanmasını engelleyen `Taints` tanımlanmıştır ve podda buna uygun `Tolerations` eksiktir.

---

## 6. Terminating (Silinirken Askıda Kalma)

Pod silinmiş olmasına rağmen durum listesinde `Terminating` olarak kalmış ve bir türlü temizlenemiyor olabilir.

```bash
# 1. Podu zorla ve hemen silin (Graceful silme beklemeden)
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

# 2. Eğer hala silinmiyorsa finalizer blokajını kaldırın
kubectl patch pod <pod-name> -n <namespace> -p '{"metadata":{"finalizers":null}}'
```

---

## 7. Pod Teşhis Akış Şeması

```
[ POD SORUNU TESPİT EDİLDİ ]
        │
        ├──► STATUS: Pending?
        │     └──► Düğüm kaynaklarını kontrol et (describe node) ve Taint/Affinity kurallarını doğrula
        │
        ├──► STATUS: CrashLoopBackOff?
        │     └──► 'kubectl logs --previous' ile son çıkış kodunu ve logları incele
        │
        ├──► STATUS: ImagePullBackOff?
        │     └──► İmaj adını ve private registry 'imagePullSecrets' ayarlarını doğrula
        │
        └──► STATUS: Terminating?
              └──► '--grace-period=0 --force' ile zorla silmeyi dene
```
