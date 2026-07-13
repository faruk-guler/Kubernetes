# Windows Konteynerleri (Windows Containers on Kubernetes)

Kubernetes varsayılan olarak Linux tabanlı iş yükleri için tasarlanmış olsa da, kurumsal dünyada hala .NET Framework bağımlılığı olan veya Windows Server API'lerine ihtiyaç duyan binlerce uygulama bulunmaktadır.
Kubernetes, küme (cluster) içerisinde hem Linux hem de **Windows Server** işçi düğümlerini (worker nodes) yan yana çalıştırabileceğiniz karma (hybrid) küme yapısını destekler.

---

## 1. Mimari Genel Bakış

Windows konteyner desteğinde bilinmesi gereken en önemli kural şudur:

* **Control Plane (Master Nodes) HER ZAMAN Linux'ta çalışmalıdır.** API Server, etcd, scheduler gibi beyin bileşenleri Windows Server üzerinde çalışamaz.
* Sadece uygulamalarınızın koşacağı **Worker Node'lar Windows Server işletim sistemine sahip olabilir**.

### Desteklenen Sürümler

Üretim (production) ortamları için kararlılık ve performans açısından **Windows Server 2022 (LTSC)** sürümü tavsiye edilir.

---

## 2. Windows Node Kurulumu ve CNI Yapılandırması

Bir Windows Server sunucusunu Kubernetes kümesine dahil etmek için sırasıyla containerd kurulumu, CNI entegrasyonu ve join işlemleri yapılır.

### Düğüm Üzerinde containerd Kurulumu (PowerShell)

```powershell
# Windows Server üzerinde containerd servisini yükleyin
winget install ContainerD.containerd

# containerd servisini başlatın
Start-Service containerd
```

### Windows CNI (Calico) Kurulumu

Windows düğümlerde ağ iletişimi sağlamak amacıyla Calico CNI script'i çalıştırılır:

```powershell
Invoke-WebRequest -Uri https://projectcalico.docs.tigera.io/scripts/install-calico-windows.ps1 | Select-Object -ExpandProperty Content | powershell
```

### Küme Katılımı (kubeadm join)

Windows düğümünüzü Linux master düğümünüze bağlamak için Master'dan aldığınız join komutunu çalıştırın:

```powershell
kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

---

## 3. Windows Pod Manifesti ve Node Seçimi

Windows podlarının Linux düğümlere planlanmasını (veya tam tersini) engellemek amacıyla **Taint & Toleration** ve **Node Selector/Affinity** stratejisi zorunludur.

### Taint Ekleme (Windows Düğümleri İşaretleme)

Sıradan Linux podlarının Windows düğümlere gidip hata vermesini önlemek için Windows düğümlerini lekeleyin (taint):

```bash
kubectl taint nodes <windows-node-adi> os=windows:NoSchedule
```

### Örnek Windows Pod Tanımı (YAML)

Aşağıdaki pod manifestosu, tainte tolerans göstererek sadece bir Windows düğümüne planlanacağını garanti eder:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [windows_konteynerleri_manifest_1.yaml](../Manifests/01_core/windows_konteynerleri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Windows Base İmaj Seçimi

Windows container imajları Linux imajlarına göre çok daha büyüktür. Microsoft resmi olarak iki temel base imaj sunar:

| İmaj Adı | Yaklaşık Boyut | İdeal Kullanım Alanı |
|:---------|---------------:|:---------------------|
| **Nano Server** | ~100 - 150 MB | .NET Core, minimal ve yeni nesil web uygulamaları |
| **Server Core** | ~3.5 GB | Klasik IIS, COM+, MSI yükleyicisi gerektiren eski (legacy) uygulamalar |

> [!WARNING]
> **Sürüm Uyumluluğu:** Windows container çekirdeği ile düğümün (host) çekirdek sürümü tam uyumlu olmalıdır. Örneğin; `ltsc2022` etiketli bir imajı sadece Windows Server 2022 yüklü bir düğümde çalıştırabilirsiniz. Aksi halde pod `CreateContainerError` hatası verecektir.

---

## 5. Linux vs. Windows Konteyner Kısıtlamaları

Windows işletim sisteminin mimari yapısı gereği, Linux'ta sıklıkla kullandığımız bazı Kubernetes özellikleri Windows düğümlerde desteklenmez:

* **HostNetwork / HostPID:** Windows düğümlerde podların ana makine ağını veya işlem tablosunu paylaşması desteklenmez.
* **Privileged Containers:** Windows podları gerçek anlamda "ayrıcalıklı (root)" modda çalıştırılamaz.
* **eBPF (Cilium):** eBPF teknolojisi tamamen Linux çekirdeğine özel olduğu için Windows düğümler üzerinde ağ politikası kontrolleri kısıtlıdır.

---

## 6. Özet

Kubernetes üzerinde Windows konteynerlerini çalıştırmak, kurumsal monolitik uygulamaları modernize etmek için harika bir geçiş köprüsüdür. Ancak yüksek kaynak tüketimi (bellek/disk) ve imaj uyumluluk zorlukları göz önüne alınarak, mümkün olan uygulamaların Linux tabanlı konteynerlere taşınması uzun vadede maliyet ve performans açısından en doğru stratejidir.
