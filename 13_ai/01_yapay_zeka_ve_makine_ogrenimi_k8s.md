# Yapay Zeka (AI/ML) ve Kubernetes Giriş

Milyarlarca parametreye sahip Büyük Dil Modellerinin (LLM) ve yapay zeka sistemlerinin hayatımıza girmesiyle birlikte, veri merkezlerindeki iş yükü profili radikal bir şekilde değişmiştir. Artık sadece standart web sunucuları değil; yüzlerce ekran kartının (GPU) birbiriyle mikro saniyeler düzeyinde haberleştiği, devasa veri işleme (data processing) ve model eğitimi (training) işlerini yönetiyoruz.

Bu bölümde, yapay zeka altyapılarının neden Kubernetes üzerinde orkestre edilmesi gerektiğini ve AI/ML iş yüklerinin (Training ve Inference) temel çalışma prensiplerini inceleyeceğiz.

---

## 1. Neden Yapay Zeka İçin Kubernetes?

Yapay zeka modellerini eğitmek veya çalıştırmak, CPU iş yüklerinden farklı olarak çok yüksek donanım maliyetleri ve özel ağ gereksinimleri (InfiniBand, RoCE vb.) doğurur. AI altyapısını manuel yönetmeye kalktığımızda şu büyük sorunlarla karşılaşırız:

- **Kaynak İsrafı:** Çok pahalı olan GPU kaynaklarının verimli kullanılmaması, şirket bütçelerini hızla eritir.
- **Güvenilirlik (Reliability) Eksikliği:** Günlerce süren bir model eğitimi sırasında tek bir sunucunun çökmesiyle tüm eğitimin yarıda kalması ve boşa gitmesi.
- **Ölçeklenebilirlik Sınırları:** Anlık gelen binlerce kullanıcı isteğinde yapay zeka modellerinin (inference) aşırı yüklenerek kilitlenmesi.

Kubernetes bu süreçte şu çözümleri sunar:

- **Dinamik GPU Tahsisi:** GPU'ları podlar arasında akıllıca paylaştırır ve boşta kalan kaynakları geri kazanır.
- **Hata Toleransı (Fault Tolerance):** Eğitim sırasında çöken bir podu, kaldığı en son kayıt noktasından (checkpoint) başka bir sunucuda otomatik olarak yeniden başlatır.
- **Metrik Tabanlı Autoscaling:** Kullanıcı trafiği arttığında model sunan podların sayısını otomatik olarak artırır (KEDA entegrasyonu ile).

---

## 2. AI/ML İş Yükü Tipleri: Training vs. Inference

Yapay zeka yaşam döngüsü temelde iki farklı aşamadan oluşur ve Kubernetes bu iki aşamayı da farklı şekillerde orkestre eder:

```
[ Model Yaşam Döngüsü ]
       │
       ├─► 1. Training (Model Eğitimi) ──► Dağıtık, Batch Job (KubeRay, Kubeflow)
       │
       └─► 2. Inference (Model Sunumu) ──► Gerçek Zamanlı, Auto-scaling (KServe, vLLM)
```

### Model Eğitimi (Training)

- **Karakteristiği:** Çok yüksek miktarda verinin GPU'lar üzerinden geçirilerek model ağırlıklarının (weights) hesaplanması sürecidir. Genellikle "Batch Job" mantığında çalışır.
- **K8s Rolü:** Dağıtık eğitimi (Distributed Training) yönetmek. Örneğin 8 sunucudaki 64 GPU'nun birbirleriyle veri senkronizasyonu yaparak tek bir büyük model eğitmesini sağlar.

### Model Sunumu (Inference)

- **Karakteristiği:** Eğitilmiş modelin üretim ortamına alınarak kullanıcılardan gelen sorulara (prompt) gerçek zamanlı olarak yanıt üretmesi sürecidir.
- **K8s Rolü:** Gözlemlenebilirlik (latency takibi), yük dengeleme (load balancing) ve anlık talebe göre hızlı pod ölçeklendirme.

---

## 3. NVIDIA Device Plugin Kurulumu

Kubernetes düğümlerinizin (nodes) üzerindeki fiziksel GPU kartlarını tanıyabilmesi ve bunları podların kullanımına sunabilmesi için kümenize bir aygıt sürücüsü eklentisi (Device Plugin) kurulmalıdır.

Aşağıdaki komutlarla Kubernetes kümenize **NVIDIA Device Plugin** kurulumunu gerçekleştirebilirsiniz:

```bash
# NVIDIA GPU Operator Helm reposunu ekleyin
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# GPU Operator'ı kurun (Sürücüleri, toolkit'i ve eklentileri otomatik kurar)
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace
```

Kurulum tamamlandıktan sonra, kümenizdeki GPU kaynaklarını şu komutla sorgulayabilirsiniz:

```bash
# GPU düğümlerini ve kapasitelerini listeleme
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpu: .status.capacity["nvidia.com/gpu"]}'
```

Artık Kubernetes API'si, düğümlerdeki GPU varlığından haberdardır. Bir pod oluştururken `resources.limits` kısmına `nvidia.com/gpu` tanımlayarak doğrudan podun içine ekran kartı atayabiliriz.

---

## 4. Özet

Kubernetes, yapay zeka altyapılarını yönetmek için standart bir işletim sistemi haline gelmiştir. Bu bölümde temelleri ve GPU entegrasyonunun nasıl yapılacağını gördük. Bir sonraki bölümde, bu pahalı GPU kaynaklarını daha verimli kullanabilmek için donanımsal ve yazılımsal paylaşım yöntemlerini (GPU Slicing ve MIG) inceleyeceğiz.
