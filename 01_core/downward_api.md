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

Aşağıda, hem Çevre Değişkenleri (Pod adı, IP ve CPU/RAM limitleri) hem de Volume Mount (Labels ve Annotations dosyaları) yöntemlerini bir arada kullanan örnek bir pod manifesti bulunmaktadır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [downward_api_manifest_1.yaml](../Manifests/01_core/downward_api_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.
