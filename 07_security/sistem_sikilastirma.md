# İşletim Sistemi ve Düğüm Sıkılaştırma (System Hardening)

Kubernetes güvenliği, pod düzeyindeki güvenlik ayarlarından önce, üzerinde çalıştığı Linux işletim sisteminin (Host OS) ve fiziksel/sanal düğümlerin (nodes) güvenliğine dayanır. Saldırganların host düzeyine sızmasını önlemek ve atak yüzeyini en aza indirmek için işletim sistemi, çekirdek (kernel) ve ağ düzeyinde sıkılaştırma (hardening) yapılması gerekir.

---

## 1. İşletim Sistemi Düzeyinde Atak Yüzeyini Azaltma

Bir Kubernetes worker node'unda sadece Kubernetes'in çalışması için gereken minimum servisler aktif olmalıdır.

* **Gereksiz Servislerin Kapatılması:** Sunucularda koşan `snapd`, `cups`, `postfix` gibi genel amaçlı servisler sistemden tamamen kaldırılmalıdır:

    ```bash
    sudo apt-get remove --purge -y snapd postfix cups
    ```

* **Açık Portların Denetlenmesi:** Node üzerinde sadece izin verilen ağ portlarının açık olduğunu doğrulamak için periyodik kontrol yapılmalıdır:

    ```bash
    ss -tlpn
    ```

* **Kullanıcı Yetki Sınırları:** Node üzerinde root dışındaki sistem kullanıcılarının shell (bash/sh) erişimleri `/usr/sbin/nologin` olarak kısıtlanmalıdır.

---

## 2. AppArmor (Uygulama Zırhı) Yapılandırması

**AppArmor**, Linux çekirdeğinde çalışan ve uygulamaların erişebileceği dosyaları, ağ yetkilerini ve diğer yetenekleri (capabilities) beyaz liste (whitelist) mantığına göre kısıtlayan bir Linux Güvenlik Modülüdür (LSM).

### AppArmor Çalışma Modları

1. **Enforce (Zorlayıcı):** Tanımlanan kısıtlamaları kesin olarak uygular ve ihlalleri engeller.
2. **Complain (Şikayetçi/Öğrenme):** İhlalleri engellemez ancak sistem loglarına (`/var/log/audit/audit.log`) kaydeder.
3. **Disabled (Devre Dışı).**

### Örnek 1: Java/Spring Boot için AppArmor Profili

Aşağıdaki profil, Java uygulamasının sadece kendi dizinine ve kütüphanelerine erişmesine izin verir, geri kalan tüm Linux disk erişimlerini engeller:

```protobuf
# /etc/apparmor.d/java-spring-app
#include <tunables/global>

profile java-spring-app flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/user-tmp>

  # Java kütüphanelerine ve sistem jar dosyalarına salt okunur erişim
  /usr/lib/jvm/java-17-openjdk-amd64/** r,

  # Uygulama koduna salt okunur ve çalıştırılabilir erişim
  /app/** r,
  /app/my-spring-app.jar r,

  # Uygulama log dizinine yazma izni
  /var/log/app/** rw,

  # Geçici dizin izni
  /tmp/** rwk,
}
```

Profili sunucuya yüklemek için:

```bash
sudo apparmor_parser -r -W /etc/apparmor.d/java-spring-app
```

### Örnek 2: Komut Satırı (Shell) Kullanımını Yasaklayan AppArmor Profili

Pod içine sızan birinin `bash` veya `sh` çalıştırmasını engellemek için:

```protobuf
# /etc/apparmor.d/no-shells
#include <tunables/global>

profile no-shells flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Shell çalıştırma yetkilerini kesin olarak engelle (deny)
  deny /bin/bash ix,
  deny /bin/sh ix,
  deny /bin/ash ix,
  deny /bin/dash ix,

  # Uygulamanın kendi dizinindeki erişimleri
  /app/** rix,
}
```

### Pod İçinde AppArmor Profilini Aktif Etme

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [sistem_sikilastirma_manifest_1.yaml](../Manifests/07_security/sistem_sikilastirma_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Seccomp (Secure Computing Mode) ile Çekirdek Çağrılarını Sınırlandırma

**Seccomp**, bir konteynerin Linux çekirdeğine gönderebileceği sistem çağrılarını (system calls - syscalls) kısıtlar.

* **AppArmor** dosya yolları ve ağ ile ilgilenirken, **Seccomp** doğrudan çekirdek çağrılarıyla (`mount`, `ptrace`, `reboot` vb.) ilgilenir.

### Örnek Seccomp JSON Profili

Aşağıdaki profil, en temel sistem çağrılarına izin verirken `write`, `read` gibi işlemleri serbest bırakır, fakat tehlikeli çağrıları engeller:

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": [
        "accept",
        "accept4",
        "bind",
        "close",
        "exit",
        "exit_group",
        "fstat",
        "listen",
        "read",
        "write"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

### Kurulum ve Kullanım

1. Oluşturulan JSON dosyası tüm düğümlerde `/var/lib/kubelet/seccomp/custom-seccomp.json` dizinine kopyalanır.
2. Pod manifestinde şu şekilde çağrılır:

```yaml
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: custom-seccomp.json
```

---

## 4. API Server Auditing (Denetim Günlükleri) Yapılandırması

Kümeye kimlerin eriştiğini, hangi istekleri gönderdiğini ve API Server'ın bunlara ne yanıt verdiğini kaydetmek en kritik güvenlik gereksinimidir.

### 1. `audit-policy.yaml` Politikası Oluşturma

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [sistem_sikilastirma_manifest_2.yaml](../Manifests/07_security/sistem_sikilastirma_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### 2. Kube-apiserver'a Entegre Etme

`/etc/kubernetes/manifests/kube-apiserver.yaml` dosyası güncellenir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [sistem_sikilastirma_manifest_3.yaml](../Manifests/07_security/sistem_sikilastirma_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Master/Control Plane Node'larının Taint Edilmesi

Kritik kontrol bileşenlerinin çalıştığı master sunuculara geliştiricilerin yanlışlıkla pod planlamasını (scheduling) engellemek için master sunucular mutlaka taint edilmelidir:

```bash
# Control plane sunucusuna NoSchedule taint'i uygulayın
kubectl taint nodes master-node-01 node-role.kubernetes.io/control-plane:NoSchedule --overwrite
```

---

## 6. Logların Uzak Sunucuya Güvenli Taşınması (Remote Shipping)

Saldırganlar sisteme sızdıklarında ilk olarak izlerini silmek için local log dosyalarını temizlerler. Bu durumu engellemek amacıyla audit logları, oluştukları an **Filebeat** veya **Fluent Bit** ajanları yardımıyla merkezi bir log yönetim sistemine (**Grafana Loki**, Elasticsearch vb.) şifreli (TLS) olarak aktarılmalıdır.
