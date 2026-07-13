# Pod ve Konteyner Güvenlik Bağlamı (SecurityContext)

**SecurityContext (Güvenlik Bağlamı)**, Kubernetes üzerindeki pod'ların ve konteynerlerin sahip olduğu Linux güvenlik parametrelerini tanımlayan yapıdır. Konteynerin hangi Linux kullanıcısı (UID) ve grubu (GID) ile çalışacağı, dosya sisteminin yazılabilir olup olmayacağı, hangi Linux çekirdek yeteneklerine (capabilities) sahip olacağı ve seccomp/AppArmor kısıtlamaları burada belirlenir. 2026 yılı kurumsal Kubernetes standartları (CIS Benchmarks ve PSS) bu ayarların zorunlu olarak yapılandırılmasını gerektirir.

---

## 1. Neden Önemli?

Konteynerler varsayılan ayarlarıyla çalıştırıldığında (SecurityContext tanımlanmadığında) ciddi güvenlik açıkları barındırırlar:

```
Varsayılan Konteyner Davranışı (Güvensiz):
  ❌ Root kullanıcısı (UID 0) olarak çalışır.
  ❌ Root dosya sistemi (Root Filesystem) tamamen yazılabilirdir.
  ❌ Neredeyse tüm Linux çekirdek yetenekleri (capabilities) aktiftir.
  ❌ Çekirdek çağrılarına (syscalls) hiçbir kısıtlama uygulanmaz.
  ❌ Host (fiziksel sunucu) ağ ve işlemci namespace'lerine erişim mümkündür.

İdeal Güvenli Konteyner Davranışı (Güvenli):
  ✅ Root olmayan (UID 1000+) standart bir kullanıcıyla çalışır.
  ✅ Salt okunur dosya sistemi (Read-only root filesystem) kullanır.
  ✅ Sadece uygulamanın çalışması için gereken minimum yetenekleri (capabilities) barındırır.
  ✅ Seccomp profili (`RuntimeDefault`) aktiftir.
  ✅ Privilege escalation (ekstra yetki yükseltme) engellenmiştir.
```

---

## 2. Pod Seviyesi vs. Konteyner Seviyesi SecurityContext

Kubernetes'te `securityContext` hem **Pod** tanımında (tüm konteynerleri etkileyecek şekilde) hem de **Container** tanımında (sadece ilgili konteyneri etkileyecek şekilde) yapılandırılabilir:

* **Pod Seviyesi:** Genellikle dosya erişim yetkileri (`fsGroup`), çalışacak standart kullanıcı (`runAsUser`) ve grup (`runAsGroup`) gibi tüm pod genelini kapsayan ayarları içerir.
* **Konteyner Seviyesi:** Ayrıcalık yükseltme engeli (`allowPrivilegeEscalation`), salt okunur dosya sistemi (`readOnlyRootFilesystem`) ve Linux yetenekleri (`capabilities`) gibi doğrudan konteyner bazlı çalışan sınırlandırmaları içerir. Konteyner seviyesindeki ayarlar, pod seviyesindeki çakışan ayarları ezer.

---

## 3. Tam Güvenli Üretim (Production) YAML Örneği

Aşağıda, kurumsal güvenlik standartlarına uygun olarak sıkılaştırılmış bir Deployment YAML tanımı yer almaktadır:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [security_context_manifest_1.yaml](../Manifests/07_security/security_context_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Linux Capabilities (Linux Yetenekleri)

Linux yetenekleri, geleneksel root (UID 0) haklarını daha küçük ve yönetilebilir parçalara böler. Konteynerimizin tüm çekirdek yetkilerine erişimini kesmek, siber saldırılarda sunucunun ele geçirilmesini engellemenin en etkili yoludur.

**Öneri:** Her zaman `drop: ["ALL"]` diyerek her şeyi silin ve sadece uygulamanın ihtiyaç duyduğu (örneğin port dinleme için `NET_BIND_SERVICE`) yetenekleri `add` ile ekleyin.

```bash
# Bir pod içinde çalışan sürecin yeteneklerini (capabilities) sorgulamak için:
cat /proc/1/status | grep Cap

# Çıkan hex kodunu anlamlı hale getirmek (decode) için:
capsh --decode=0000000000000400
# Sonuç: cap_net_bind_service (sadece port bağlama yetkisi aktif)
```

---

## 5. Seccomp Profili (Secure Computing Mode)

Seccomp, konteyner içinden Linux çekirdeğine (Kernel) gönderilen sistem çağrılarını (syscalls) filtreler. Kubernetes 1.19+ ve 2026 kurumsal mimarilerinde varsayılan olarak **RuntimeDefault** profilinin kullanılması zorunludur:

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
```

Bu ayar, konteynerin tehlikeli çekirdek çağrıları (örneğin `reboot`, `sys_ptrace`) göndermesini engeller.

---

## 6. AppArmor (GKE ve AKS Standartları)

AppArmor, işletim sistemi düzeyinde programların yeteneklerini kısıtlayan bir Linux güvenlik modülüdür. GKE veya AKS gibi bulut servislerinde AppArmor profilleri pod'lara şu şekilde uygulanır:

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/application: runtime/default
```

*Not: Kubernetes 1.30+ ile birlikte AppArmor, doğrudan `securityContext.appArmorProfile` alanı üzerinden yapılandırılabilmektedir.*

---

## 7. Privileged Mode (Ayrıcalıklı Mod) - Asla Kullanmayın

Konteyner YAML dosyasına `privileged: true` yazılması, konteyner içindeki root kullanıcısına doğrudan host (worker node) işletim sistemindeki root haklarını verir.

> [!CAUTION]
> **Privileged: true Riskleri:** Bir saldırgan privileged modda çalışan bir konteyneri hacklediğinde, doğrudan fiziksel makinenin disklerine erişebilir, ağ kartını dinleyebilir ve tüm kümü kontrol altına alabilir. Üretim ortamlarında bu parametre politika motorları ile kesinlikle yasaklanmalıdır.

---

## 8. Kümedeki Güvenlik Açıklarını Denetleme (jq ve kubectl)

Kümenizde koşan pod'ların SecurityContext yapılandırmalarını hızlıca sorgulamak ve kurallara uymayanları bulmak için şu komutları kullanabilirsiniz:

```bash
# 1. Kümedeki "runAsNonRoot" parametresi tanımlanmamış veya root olarak çalışan podları bulun:
kubectl get pods -A -o json | jq -r '
  .items[] |
  select(
    .spec.securityContext.runAsNonRoot != true and
    (.spec.securityContext.runAsUser == null or .spec.securityContext.runAsUser == 0)
  ) |
  "\(.metadata.namespace)/\(.metadata.name)"'

# 2. Kümedeki privileged (ayrıcalıklı) modda çalışan tehlikeli konteynerleri bulun:
kubectl get pods -A -o json | jq -r '
  .items[] |
  .metadata as $meta |
  .spec.containers[] |
  select(.securityContext.privileged == true) |
  "\($meta.namespace)/\($meta.name)/\(.name)"'

# 3. production isim alanında dosya sistemi salt okunur (readOnlyRootFilesystem) YAPILMAMIŞ podları listeleyin:
kubectl get pods -n production -o json | jq -r '
  .items[] |
  .metadata as $meta |
  .spec.containers[] |
  select(.securityContext.readOnlyRootFilesystem != true) |
  "\($meta.namespace)/container:\(.name)"'
```

---

## 9. Özet: Minimum Güvenli Konfigürasyon Kontrol Listesi

1. [ ] `runAsNonRoot: true` pod düzeyinde ayarlandı mı?
2. [ ] `runAsUser` ve `runAsGroup` için root olmayan (10000-60000 arası) bir ID belirlendi mı?
3. [ ] `allowPrivilegeEscalation: false` konteyner düzeyinde tanımlandı mı?
4. [ ] `readOnlyRootFilesystem: true` yapılandırıldı mı? (Yazılması gereken geçici yerler için `emptyDir` mount edildi mi?)
5. [ ] `capabilities.drop: ["ALL"]` yapılarak gereksiz tüm Linux çekirdek yetkileri sıfırlandı mı?

> [!IMPORTANT]
> `runAsNonRoot: true` tek başına yeterli değildir; imajınızın (Dockerfile) root olmayan bir kullanıcıyla başlayacak şekilde paketlendiğinden emin olmalı veya `runAsUser` değeriyle bunu açıkça belirtmelisiniz. Aksi takdirde Kubernetes podun çalışmasını durdurur.
