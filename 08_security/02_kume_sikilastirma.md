# Küme Sıkılaştırma ve Güvenlik Denetimi (Cluster Hardening)

Kubernetes kümenizi dışarıdan ve içeriden gelebilecek gerçek dünya siber saldırılarına karşı korumak için kontrol düzleminin (control plane), ağ bağlantılarının ve düğüm erişimlerinin sıkılaştırılması (**hardening**) hayati önem taşır. Bu dokümanda, küme güvenliğini test etmek ve sıkılaştırmak için uygulanması gereken pratik adımları ele alacağız.

---

## 1. API Server Sıkılaştırma (Control Plane Hardening)

API Server, kümenin kontrol merkezidir. Bu sunucunun güvenliğini artırmak için aşağıdaki parametreler kontrol edilmelidir:

### Kubelet İletişimi TLS Doğrulaması

API Server'ın kubelet ile konuşurken TLS doğrulaması yapmasını sağlamak için şu bayraklar (`flags`) etkinleştirilmelidir:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
- --kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt
- --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt
- --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key
```

### Güvenli Olmayan Portun Kapatılması

Eski Kubernetes sürümlerinde bulunan ve şifresiz/yetkisiz yerel erişim sağlayan port (`8080`) tamamen devre dışı bırakılmalıdır:

```yaml
- --port=0
```

---

## 2. etcd Güvenliği ve Şifreleme

Kubernetes'in tüm verilerini sakladığı `etcd` veritabanı, sadece API Server'ın erişebileceği şekilde yerel ağda sınırlandırılmalı ve TLS sertifikaları ile şifrelenmelidir.

### etcd Ağ Yapılandırması (etcd Flags)

```bash
# etcd.yaml içinde sadece localhost ve yerel TLS ile dinleme yapılması sağlanır:
--listen-client-urls=https://127.0.0.1:2379
--advertise-client-urls=https://127.0.0.1:2379
--cert-file=/etc/kubernetes/pki/etcd/server.crt
--key-file=/etc/kubernetes/pki/etcd/server.key
--peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
--client-cert-auth=true # Sadece geçerli istemci sertifikası olanları kabul et
```

---

## 3. Node (Sunucu) Seviyesinde SSH Sıkılaştırması

Kubernetes worker node'larına erişimi kısıtlamak, sunucu katmanındaki sızmaları engeller. SSH bağlantıları sadece belirli bir **Jump-Host (Bastion Host)** üzerinden ve şifre kullanılmadan (sadece SSH Key ile) yapılmalıdır.

```ini
# /etc/ssh/sshd_config dosyasında yapılacak güvenlik ayarları:
PasswordAuthentication no     # Şifreyle girişi tamamen engelle
AllowUsers admin              # Sadece admin kullanıcısına izin ver
AllowGroups sre-team          # Sadece bu grubun SSH erişimine izin ver
X11Forwarding no              # Grafik arayüz yönlendirmesini kapat
```

Yapılandırmadan sonra SSH servisi yeniden başlatılır:

```bash
sudo systemctl restart sshd
```

---

## 4. Küme Güvenliğini Doğrulama ve Audit Kontrol Listesi

Kümenizin dış dünyadan ne kadar izole olduğunu test etmek için aşağıdaki pratik komutları ve doğrulama testlerini kullanabilirsiniz:

```bash
# 1. Anonim İstek Kontrolü (Anonymous Auth)
# Kümeye sahte/bozuk bir token ile anonim istek atıldığında 401 Unauthorized dönmelidir:
curl -k https://<API_SERVER_IP>:6443/api --header "Authorization: Bearer bad-token"

# 2. etcd Portunun Dışa Açıklık Kontrolü
# etcd portunun (2379) dış ağlara kapalı olduğunu doğrulamak için nmap taraması yapın (Port kapalı/filtered olmalıdır):
nmap -p 2379 <NODE_EXTERNAL_IP>

# 3. Root Yetkisiyle Çalışan Podları Bulma
# Kümedeki podların hangi kullanıcı ID'si (UID) ile çalıştığını kontrol edin:
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" runAsUser: "}{.spec.containers[*].securityContext.runAsUser}{"\n"}{end}'

# 4. Ayrıcalıklı (Privileged) Podları Bulma
# Kümede "Tanrı Modunda" (privileged: true) çalışan tehlikeli podları listeleyin:
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" privileged: "}{.spec.containers[*].securityContext.privileged}{"\n"}{end}'
```

---

## 5. Trivy ile Canlı Küme Güvenlik Denetimi

Açık kaynaklı güvenlik tarayıcısı **Trivy** ile tüm Kubernetes kümenizin anlık zafiyet durumunu sorgulayabilirsiniz:

```bash
# 1. Küme genelinde özet güvenlik raporu
trivy k8s --report summary cluster

# 2. Sadece HIGH (Yüksek) ve CRITICAL (Kritik) seviyedeki açıkları raporlama
trivy k8s --severity HIGH,CRITICAL --report all cluster
```

> [!CAUTION]
> **Üretim Ortamı Uyarısı:** API Server üzerinde `--anonymous-auth=false` gibi parametreleri değiştirmeden önce, küme içi izleme (Prometheus) veya loglama araçlarınızın API Server'a anonim istek atıp atmadığını doğrulayın. Aksi takdirde, bu kontrolleri kapatmak bazı sistem araçlarınızın API Server ile bağlantısını koparabilir.
