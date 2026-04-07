# WebAssembly (Wasm) İş Yükleri

Konteynerlerin yerini alan veya onları tamamlayan bir sonraki devrim: **WebAssembly (Wasm)**. Konteynerlere (Containerd/Docker) göre %90 daha hızlı ayağa kalkarlar, sadece birkaç megabayt boyutundadırlar ve Linux çekirdeği zafiyetlerinden tamamen izoledirler.

---

## 2.1 Wasm Neden Önemli?

- **Hız:** Geleneksel konteynerler başlatılırken milisaniyeler-saniyeler harcanırken, Wasm modülleri mikrosaniyeler içinde başlatılır.
- **Portabilite:** "Build once, run anywhere" (Bir kez derle, her yerde çalıştır). İşlemci mimarisinden (ARM ya da x86) tamamen bağımsızdır.
- **Güvenlik:** Kendi kum havuzunda (Sandbox) çalıştığı için host makineye zarar verme ihtimali container'lara oranla çok daha düşüktür.

---

## 2.2 Kubernetes Üzerinde Wasm (SpinKube & containerd-wasm)

2026'da Kubernetes'e bir Wasm modülü göndermek, bir Docker imajı göndermek kadar kolaydır. RuntimeClass yardımıyla Kubelet'e pod'un bir Container değil, Wasm olduğu belirtilir.

Aşağıdaki komut cluster'a WebAssembly eklentisini (Kwasm/SpinKube) kurar:

```bash
# Kwasm Operator kurulumu (Node'lara Wasm runtime'ları dağıtır)
helm repo add kwasm http://kwasm.sh/kwasm-operator/
helm install -n kwasm --create-namespace kwasm-operator kwasm/kwasm-operator
```

---

## 2.3 Wasm İş Yükü (Pod) Dağıtma

Cluster hazırlandıktan sonra, klasik bir OCI imajı (ancak Wasm kodunu tutan) dağıtılır:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wasm-hello-world
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wasm-hello
  template:
    metadata:
      labels:
        app: wasm-hello
    spec:
      runtimeClassName: wasmedge   # !!! En kritik satır. Wasm kullanılacağını bildirir.
      containers:
      - name: wasm-app
        image: docker.io/michaelirwin244/wasm-hello-world:latest
        ports:
        - containerPort: 8080
```

> [!TIP]
> Serverless fonksiyonlar veya Edge Bilişim (IoT) cihazları için Wasm, Kubernetes ekosistemindeki en güçlü seçenektir. KEDA (Bkz: Bölüm 08) ile birleştirildiğinde 0'dan 1000 replikaya sadece birkaç salisede ulaşabilirsiniz!

---
*← [AI/ML Ops](01_ai_ml_kubernetes.md) | [Ana Sayfa](../README.md)*
