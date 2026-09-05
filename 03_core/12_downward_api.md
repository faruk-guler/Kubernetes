# Downward API: Pod Meta-verilerini Konteynerlere Aktarma

Kubernetes'te uygulamalarımızı çalıştırırken bazen uygulamamızın (kodumuzun) kendi çalıştığı ortamla ilgili bazı bilgilere erişmesi gerekir. Örneğin; uygulamanın hangi **Pod adında**, hangi **IP adresinde** veya hangi **Namespace** altında çalıştığını bilmesi gerekebilir.

Bu tür bilgileri uygulamanın içine sabit (hardcoded) olarak yazmak esnekliği öldürür. Kubernetes bu sorunu çözmek için **Downward API** adında bir mekanizma sunar. Downward API, pod'a ait meta-verileri konteynerin içine iki farklı şekilde aktarabilir: **Çevre Değişkenleri (Environment Variables)** veya **Dosyalar (Volumes)**.

---

## 1. Çevre Değişkenleri (Environment Variables) Olarak Aktarma

Pod'un meta-verilerini veya kaynak (resources) sınırlarını doğrudan konteynerin çevre değişkenlerine atayabiliriz.

### A. Pod Bilgilerini Aktarma

Aşağıdaki alanlar çevre değişkeni olarak tanımlanabilir:

* `metadata.name` (Pod Adı)
* `metadata.namespace` (Namespace Adı)
* `metadata.uid` (Pod'un Benzersiz Kimliği)
* `status.podIP` (Pod'un IP Adresi)
* `spec.nodeName` (Pod'un çalıştığı Düğüm/Node Adı)
* `spec.serviceAccountName` (Kullanılan ServiceAccount Adı)

### B. Kaynak Limitlerini Aktarma (Resource Fields)

Konteynerin kendisine atanan CPU ve RAM limitlerini de Downward API ile okuyabiliriz:

* `limits.cpu`
* `limits.memory`
* `requests.cpu`
* `requests.memory`

> [!TIP]
> **JVM (Java) ve Python Bellek Yönetimi:** Java gibi dillerde JVM'in RAM limitlerini (`-Xmx`) ayarlarken konteynerin RAM limitini bilmek çok önemlidir. Downward API ile `limits.memory` değerini okuyup, bir başlangıç scriptiyle bu değeri JVM parametrelerine dinamik olarak besleyebilirsiniz.

---

## 2. Dosya (Volume Mount) Olarak Aktarma

Pod etiketleri (labels) veya açıklamaları (annotations) gibi zamanla dinamik olarak değişebilen verileri çevre değişkenlerine atamak zordur (çünkü çevre değişkenleri pod çalışırken güncellenemez).

Bu durumlarda Downward API verileri **Volume (Dosya)** olarak bağlanır. Kubernetes, etiketler veya açıklamalar değiştiğinde bu dosyaları arka planda **anında günceller**.

Konteyner içinde belirtilen dosyalar (Örn: `/etc/podinfo/labels`) okunarak güncel etiketlere anında erişilebilir.

---

## 3. Örnek Yapılandırma Manifesti

Aşağıda, hem Çevre Değişkenleri (`fieldRef`) hem de Dosya Bağlama (`downwardAPI` volume) yöntemlerini bir arada gösteren yalın bir Pod tanımlanmıştır:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: downward-api-demo
  labels:
    app: payment
spec:
  containers:
    - name: app
      image: alpine
      command: ["sleep", "3600"]
      env:
        # 1. Pod adını ortam değişkenine aktarma
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        # 2. Pod IP adresini ortam değişkenine aktarma
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      volumeMounts:
        - name: podinfo
          mountPath: /etc/podinfo
  volumes:
    # 3. Pod etiketlerini dinamik dosya (/etc/podinfo/labels) olarak sunma
    - name: podinfo
      downwardAPI:
        items:
          - path: "labels"
            fieldRef:
              fieldPath: metadata.labels
```

---

## Özet

Downward API, pod meta-verilerini (isim, IP, node, kaynak limitleri ve etiketler) dışarıdan konfigürasyon enjekte etmeye gerek kalmadan doğrudan konteyner içine aktarır. Bu sayede mikroservisler, çalıştıkları Kubernetes ekosistemiyle dinamik ve ayrık (loosely-coupled) bir uyum yakalar.
