# 🎓 Kubernetes Mastery Syllabus (Dibine Kadar Öğrenme Rehberi)

Aşağıdaki **5 Seviyeli Eğitim Müfredatı**, kütüphanede yer alan 60'tan fazla dosyayı sıradan bir okuma parçası olmaktan çıkarıp, sizi "System Architect" seviyesine ulaştıracak interaktif bir laboratuvar rotasıdır. Her seviyedeki belgeleri sırasıyla okumalı ve "Hands-On Lab" (Pratik Görev) görevlerini kendi terminalinizde kasten bozup onararak tecrübe etmelisiniz.

---

## 🟤 Seviye 1: The Foundation (Temellerin Sarsılması)
Kubernetes'in yüzeyiyle değil, beyniyle tanıştığınız yerdir. API Server nasıl düşünür, Scheduler karar ağacı nasıl çalışır?
* **Okunacaklar:**
  1. [Bölüm 1 - Mimari ve Bileşenler](01_temel_ve_mimari/02_mimari_ve_bilesenler.md)
  2. [Bölüm 2 - RKE2 Kurulumu](02_kurulum/04_rke2_kurulum.md)
  3. [Bölüm 1 - İleri Pod Teknikleri](01_temel_ve_mimari/04b_ileri_pod_teknikleri.md)
* **💻 Hands-On Lab Görevi:**
  - `kube-system` namespace'ine girip `kube-apiserver` static pod manifest'inin içine girin ve manifesti bozun (Yanlış bir argüman yazın). API Server çöktüğünde `crictl` veya `containerd` komutlarıyla ayağa kalkmayan container logunu yakalayıp düzeltmeye çalışın. Her şeyin bir Linux Process'i olduğunu kendi gözlerinizle görün.

---

## 🔵 Seviye 2: Traffic & The Nervous System (Kan Dolaşımı)
Ağ bağlantılarının "sihir" olmadığını, her şeyin Kernel bazlı IPTables veya eBPF haritalarından ibaret olduğunu öğrendiğiniz seviyedir. Ingress ölür, Gateway API doğar.
* **Okunacaklar:**
  1. [Bölüm 3 - Gateway API v2](03_ag_ve_trafik/01_gateway_api.md)
  2. [Bölüm 3 - Service Mesh Istio](03_ag_ve_trafik/04_service_mesh_istio.md)
  3. [Bölüm 9 - Argo Rollouts & Canary](09_ileri_deployment/01_argo_rollouts.md)
* **💻 Hands-On Lab Görevi:**
  - Yerel cluster'ınıza MetalLB kurun. Gateway API yapılandırarak `test.local` DNS'ine gelen trafiği `%90 v1`, `%10 v2` şeklinde bölün. Istio Sidecar enjekte edilmiş bir Pod'dan diğerine giden trafiği `tcpdump` ile izleyip tamamen şifrelenmiş (mTLS) olduğunu kanıtlayın.

---

## 🔴 Seviye 3: Persistence & Hard Hat (Kalıcılık ve Yıkım)
Sunucu fişlerinin çekildiği, disklerin bozulduğu ve her şeyin kaosa sürüklendiği senaryoların altından kalkma ustuluğu.
* **Okunacaklar:**
  1. [Bölüm 7 - Longhorn ile Block Storage](07_depolama_ve_veri/03_longhorn_storage.md)
  2. [Bölüm 8 - HPA ve VPA Scaling](08_ileri_operasyonlar/05_hpa_vpa_scaling.md)
  3. [Bölüm 8 - etcd Disaster Recovery (Quorum Loss)](08_ileri_operasyonlar/08_etcd_disaster_recovery.md)
* **💻 Hands-On Lab Görevi:**
  - (Sanal makinelerdeki test ortamınızda) etcd cluster'ını oluşturan makinelerden birinin diskini kalıcı olarak silin veya formatlayın. Kalan snapshot'ı kullanarak cluster API'sini tekrar yanıt verir (Active) duruma getirecek `etcdctl snapshot restore` operasyonunu deneyimleyin.

---

## ⚫ Seviye 4: The Creator Mode (Yaratıcı Mod - Kara Kuşak)
Hazır araçları (Helm, Rancher) kullanmayı bırakıp, **kendi Kubernetes objenizi ve mantığınızı Go diliyle yazdığınız** seviyedir. Mimarinin zirvesidir.
* **Okunacaklar:**
  1. [Bölüm 1 - CRD ve Operator](01_temel_ve_mimari/07_crd_ve_operator.md)
  2. [Bölüm 1 - Go ile Kubebuilder Operator Yazımı](01_temel_ve_mimari/07b_operator_gelistirme_kubebuilder.md)
  3. [Bölüm 11 - Crossplane Platform Engineering](11_maliyet_ve_platform/03_crossplane_platform_engineering.md)
* **💻 Hands-On Lab Görevi:**
  - `Kubebuilder` kullanarak `OyunSunucusu` adında kendi CRD'nizi ve Operator'ınızı Golang dilinde yazın. Cluster'a kurup, `kubectl apply -f oyun-sunucum.yaml` tetiklediğinizde arka planda operator'ınızın Deployment ve Service'leri otomatik ürettiğini görün.

---

## 🌌 Seviye 5: The Absolute Core (Mutlak Çekirdek - Uç Nokta)
2026 şartlarında bile çok az mühendisin cesaret edip girebildiği, sınırın ötesi teknolojilerdir.
* **Okunacaklar:**
  1. [Bölüm 6 - eBPF ile Deep Tracing (Kernel Gözlemi)](06_gozlemlenebilirlik/04_ebpf_ile_deep_tracing.md)
  2. [Bölüm 5 - SPIRE ile Zero-Trust Ağ Kimliği](05_guvenlik/07_spiffe_spire_zero_trust.md)
  3. [Bölüm 12 - Local LLM için NVIDIA MIG GPU Dilimleme](12_ai_ml_ve_ekosistem/03_gpu_dilimleme_ve_mig.md)
  4. [Bölüm 3 - BGP ve Cilium ClusterMesh](03_ag_ve_trafik/05_ebpf_bgp_clustermesh_cilium.md)
* **💻 Hands-On Lab Görevi:**
  - Kendi cluster'ınızdaki bir Pod'a dışarıdan (Sidecar olmadan) sadece Linux Kernel'inden yakalama yaparak (Tetragon ile) TCP/UDP trace'leri çekin. Parolaları ve Secret'ları rafa kaldırıp, birbirini hiç bilmeyen iki Pod'un TLS üzerinden (SPIFFE ID'siyle) kriptografik el sıkışma yapmasını sağlayın.

---
> *Eğer bu 5 seviyedeki görevleri kırıp dökerek kendi bilgisayarınızda başarabilirseniz, Kubernetes'in dibini görmüş olursunuz. Sizin asıl eğitim alanınız artık dokümanlar değil, "Terminal" ortamınızdır. Başarılar mimar!*
