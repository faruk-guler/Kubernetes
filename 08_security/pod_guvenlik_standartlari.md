# Pod Güvenlik Standartları (Pod Security Standards - PSS & PSA)

Kubernetes'te pod düzeyinde güvenliğin yönetilmesi, küme güvenliğinin temelini oluşturur. Eski sürümlerde kullanılan karmaşık `PodSecurityPolicy` (PSP) mekanizması, yerini Kubernetes 1.25 itibarıyla tamamen **Pod Security Standards (PSS)** ve bunu uygulayan **Pod Security Admission (PSA)** altyapısına bırakmıştır. Bu dokümanda, PSS profillerini, PSA modlarını, küme genelinde varsayılan yapılandırmayı ve geçiş stratejilerini inceleyeceğiz.

---

## 1. Neden PodSecurityPolicy (PSP) Kaldırıldı?

PSP mekanizması son derece karmaşıktı:

* Kullanıcı yetkilendirmesi (RBAC) ile doğrudan entegre çalışıyordu ve beklenmedik yetki sızıntılarına yol açabiliyordu.
* Hatalı yapılandırılması çok kolaydı; bu durum podların çalışmamasına ya da fark edilmeden çok geniş yetkiler verilmesine neden oluyordu.
* Kubernetes API sunucusunun performansını olumsuz etkiliyordu.

**Pod Security Admission (PSA)** ise karmaşıklığı ortadan kaldırır: Sadece 3 farklı güvenlik profili ve namespace düzeyinde etiketler (labels) kullanılarak aktif edilir.

---

## 2. Üç Güvenlik Profili (Pod Security Standards)

Kubernetes, güvenlik gereksinimlerine göre tanımlanmış üç farklı standart profil sunar:

### A. Privileged (Kısıtsız)

Hiçbir kısıtlama uygulanmaz. İşletim sistemi düzeyinde tam yetki (root) gerektiren altyapı pod'ları için tasarlanmıştır.

* **Kimler kullanır:** `kube-system` bileşenleri, CNI (ağ) sürücüleri (Cilium, Calico), izleme ajanları, CSI depolama sürücüleri.

### B. Baseline (Temel Kısıtlamalar)

En bilinen ve yaygın kullanılan yetki yükseltme (privilege escalation) açıklarını kapatır, ancak geliştiricileri ve uygulamaları aşırı sıkı kısıtlamalarla zorlamaz. Standart uygulamalar için en ideal başlangıç seviyesidir.

* **Neleri engeller:**
  * `hostNetwork`, `hostPID` ve `hostIPC` kullanımlarını.
  * Ayrıcalıklı konteynerleri (`privileged: true`).
  * Sunucu dizinlerinin bağlanmasını (`hostPath` volumes).
  * Tehlikeli Linux yeteneklerini (`NET_RAW`, `SYS_ADMIN` vb.).

### C. Restricted (En Sıkı)

Yüksek güvenlik gerektiren, hassas veri işleyen (Finans, Sağlık vb.) ortamlar için tasarlanmış sert bir profildir. Konteyner güvenliğinin en iyi uygulamalarını (best practices) zorunlu kılar.

* **Temel kuralları:**
  * `runAsNonRoot: true` olmak zorundadır.
  * `allowPrivilegeEscalation: false` olmak zorundadır.
  * Sadece güvenli volume türlerine (configMap, emptyDir, secret, PVC vb.) izin verilir.
  * `seccompProfile` alanı `RuntimeDefault` ya da `Localhost` olarak ayarlanmalıdır.
  * Tüm Linux kernel capabilities droplanmalıdır (`drop: ["ALL"]`).

---

## 3. Pod Security Admission (PSA) Kontrol Modları

Güvenlik profillerini namespace düzeyinde uygulamak için üç farklı mod bulunur. Bir isim alanında bu modların hepsi aynı anda veya farklı seviyelerde (Örn: enforce=baseline, warn=restricted) çalışabilir:

* **enforce:** Kurallara uymayan podların oluşturulmasını kesinlikle engeller ve hata döndürür.
* **warn:** Kurallara uymayan podların oluşturulmasına izin verir ancak kullanıcıya terminalde uyarı (Warning) mesajı gösterir.
* **audit:** Kurallara uymayan podları engellemez ama denetim günlüklerine (audit logs) hata kaydı yazar.

### PSA Modlarını Namespace Üzerinde Etkinleştirme

Bir isim alanında kuralları devreye almak oldukça basittir:

```bash
# production namespace'ini "restricted" profiliyle zorunlu kıl (enforce) ve uyar (warn)
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

# Namespace üzerinde kural uygulamadan önce etkilenecek podları simüle etme (dry-run)
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  --dry-run=server
```

---

## 4. Restricted Profil ile Uyumlu Örnek Pod YAML

Restricted modunun uygulandığı bir isim alanında sorunsuz çalışabilecek örnek bir pod tanımı:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pod_guvenlik_standartlari_manifest_1.yaml](../Manifests/07_security/pod_guvenlik_standartlari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Küme Genelinde Varsayılan Profil Yapılandırması

Tüm yeni oluşturulan isim alanları için varsayılan bir güvenlik politikası belirlemek amacıyla API Server konfigürasyonunda bir `AdmissionConfiguration` tanımlanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pod_guvenlik_standartlari_manifest_2.yaml](../Manifests/07_security/pod_guvenlik_standartlari_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

API Server manifest dosyasına (`/etc/kubernetes/manifests/kube-apiserver.yaml`) şu satır eklenir:
`--admission-control-config-file=/etc/kubernetes/admission-control/pod-security.yaml`

---

## 6. Mevcut Kümedeki Durumu Değerlendirme

Kümenizdeki mevcut podların ve isim alanlarının güvenlik profillerine uyumluluğunu test etmek için:

```bash
# 1. Belirli bir isim alanındaki podların durumunu dry-run ile sorgulama
kubectl label namespace my-namespace \
  pod-security.kubernetes.io/enforce=restricted \
  --dry-run=server 2>&1 | grep "Warning"

# 2. Kümedeki tüm namespace'leri restricted moduna göre tarayıp raporlama
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== İsim Alanı: $ns ==="
  kubectl label namespace $ns \
    pod-security.kubernetes.io/enforce=restricted \
    --dry-run=server 2>&1 | grep -i "warning\|error" || echo "✅ Tamamen Uyumlu"
done
```

---

## 7. Kyverno ile Ek Politikaların Entegrasyonu

PSA temel güvenlik kontrollerini (kullanıcı yetkileri, dosya sistemleri vb.) mükemmel şekilde çözer. Ancak şirkete özel kurallar (örneğin imaj ismi denetimi) için **Kyverno** gibi politika motorları ile birlikte çalışmalıdır.

Aşağıdaki Kyverno politikası, PSA restricted profiline benzer şekilde, tüm podlarda `allowPrivilegeEscalation: false` olmasını denetler ve uymayanları reddeder:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pod_guvenlik_standartlari_manifest_3.yaml](../Manifests/07_security/pod_guvenlik_standartlari_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 8. Geçiş Stratejisi: PSP'den PSA'ya Geçiş Adımları

Canlı ortamdaki uygulamaları kesintiye uğratmadan yeni güvenlik modeline geçirmek için şu adımlar izlenmelidir:

1. **Adım 1 (Audit Modu):** Namespace düzeyinde audit etiketini açın. Böylece podlar engellenmez, fakat ihlal kayıtları toplanır:

    ```bash
    kubectl label namespace production pod-security.kubernetes.io/audit=restricted
    ```

2. **Adım 2 (Log İnceleme):** Kümedeki logları ve event kayıtlarını izleyerek hangi podların uyarılara takıldığını tespit edin:

    ```bash
    kubectl get events -n production | grep "PodSecurity"
    ```

3. **Adım 3 (Düzeltme):** İhlali olan podların `securityContext` yapılandırmalarını güncelleyin.
4. **Adım 4 (Warn Modu):** Geliştiricilere de uyarı vermesi için warn etiketini etkinleştirin:

    ```bash
    kubectl label namespace production pod-security.kubernetes.io/warn=restricted
    ```

5. **Adım 5 (Enforce Modu):** Tüm podlar uyumlu hale geldikten sonra kuralı kesin olarak zorunlu kılın:

    ```bash
    kubectl label namespace production pod-security.kubernetes.io/enforce=restricted
    ```
