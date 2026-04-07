# Gelişmiş GPU Yönetimi ve Dilimleme

LLM'ler ve derin öğrenme modelleri (LLaMA, GPT türevleri) devasa GPU gücü gerektirir. Ancak her geliştirici ortamına (veya küçük Inference servisine) fiziksel bir A100 GPU (80GB) tahsis etmek muazzam bir maliyettir. İşte bu yüzden fiziksel GPU Kubernetes üzerinde "**Dilimlenerek (Slicing)**" paylaşılır.

---

## 3.1 Time-Slicing (Yazılımsal Paylaşım)

Kubernetes NVIDIA Device Plugin yapılandırması değiştirilerek, 1 fiziksel GPU'nun atıyorum **10 farklı Pod** tarafından (sanki her birinin GPU'su varmış gibi) eşzamanlı kullanılması sağlanır. Kaynaklar (VRAM) paylaşımlı olduğu için Noisy Neighbor (gürültülü komşu) sorunu yaşanabilir.

Aşağıdaki `ConfigMap` ile Node'lara Time-Slicing kuralları verilir:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: device-plugin-config
  namespace: kube-system
data:
  any.yaml: |
    version: v1
    flags:
      migStrategy: "none"
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 10      # 1 GPU'yu 10 parçaya böl
```

Bu ayarla bir Node'da 1 fiziksel GPU olsa bile `kubectl get nodes` çıktısında Capacity alanında `nvidia.com/gpu: 10` görünür!

---

## 3.2 Multi-Instance GPU (MIG) (Donanımsal Paylaşım)

NVIDIA A100 / H100 gibi modern kartlarda bulunan özelliktir. Çip fiziksel olarak (ve VRAM olarak) bağımsız parçalara bölünür. Pod'lar birbirinden kesinlikle etkilenmez.

MIG modunu aktif etmek için önce Node üzerinde MIG etkinleştirilir:
```bash
sudo nvidia-smi -i 0 -mig 1
```

Ardından Controller üzerinden spesifik profiller seçilir (Örn: 1 adet A100'den 7 adet 10GB'lık GPU çıkartmak):
```yaml
# NVIDIA MIG Profili
version: v1
flags:
  migStrategy: "mixed"
```

Ve Pod bu MIG profiline talepte bulunur:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: llm-inference-pod
spec:
  containers:
  - name: vllm-server
    image: vllm/vllm-openai:latest
    resources:
      limits:
        nvidia.com/mig-1g.10gb: 1   # Fiziksel kart değil, 10GB'lık donanımsal dilim talep ediliyor!
```

> [!WARNING]
> MIG profilleri kalıcı donanım yalıtımı sağlarken, Time-Slicing esneklik sağlar. Eğitim (Training) görevleri için bütün GPU tahsisi önerilirken, Sunum (Inference / KServe) için Time-Slicing veya MIG idealdir.

---
*← [Ana Sayfa](../README.md)*
