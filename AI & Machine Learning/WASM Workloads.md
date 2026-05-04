# WebAssembly (WASM) Workloads on Kubernetes

WebAssembly, tarayıcının ötesinde sunucu tarafında da çalışan, hafif ve hızlı başlayan bir ikili format standardıdır. Kubernetes'te WASM, container alternatifi veya tamamlayıcısı olarak 2024'ten itibaren olgunlaşmaya başlamıştır.

---

## WASM vs Container

```
Container:
  Başlatma süresi: ~100ms - birkaç saniye
  Bellek: MB - GB
  OS bağımlılığı: Var (Linux namespace)
  İzolasyon: cgroup + namespace
  Taşınabilirlik: OCI image ile sağlanır

WASM:
  Başlatma süresi: <1ms (microsaniye düzeyinde)
  Bellek: KB - MB
  OS bağımlılığı: Yok (WASI sandbox)
  İzolasyon: Capability-based (sandbox model)
  Taşınabilirlik: Donanım bağımsız (compile once, run anywhere)
```

**Ne zaman WASM tercih edilmeli?**
- Fonksiyon düzeyinde (serverless, FaaS) çalışacak kısa ömürlü workload'lar
- Cold-start süresinin kritik olduğu durumlar
- Edge computing (düşük kaynak ortamı)
- Güvenilmeyen kod çalıştırma (3rd party plugin sistemi)

---

## WASM Runtime'ları

| Runtime | Özellik | Kullanım |
|:--------|:--------|:---------|
| **WasmEdge** | Hızlı, WASI destekli, OCI uyumlu | Production, AI inference |
| **Wasmtime** | Bytecode Alliance referans impl. | Genel amaç |
| **Spin (Fermyon)** | HTTP-first WASM framework | Microservice |
| **Wasm Workers Server** | Edge proxy entegrasyonu | CDN edge |

---

## containerd WASM Shim

Kubernetes, container runtime olarak containerd kullanır. WASM workload'ları için `runwasi` shim eklenir:

```bash
# containerd için WasmEdge shim kurulumu (her node'da)
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash
sudo systemctl restart containerd

# RuntimeClass oluştur
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: wasmedge
handler: wasmedge
EOF
```

---

## WASM Pod Dağıtımı

```yaml
# WASM image — OCI formatında, .wasm dosyası içerir
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wasm-api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wasm-api
  template:
    metadata:
      labels:
        app: wasm-api
    spec:
      runtimeClassName: wasmedge    # ← WASM runtime kullan
      containers:
      - name: api
        image: ghcr.io/company/wasm-api:v1.0
        # ⚠️ WASM image = sadece .wasm binary içerir, OS katmanı yok
        resources:
          limits:
            memory: "32Mi"          # Container'a göre çok düşük
            cpu: "50m"
          requests:
            memory: "8Mi"
            cpu: "10m"
```

---

## Spin Framework (HTTP WASM Microservice)

```toml
# spin.toml — uygulama konfigürasyonu
spin_manifest_version = 2

[application]
name = "order-api"
version = "1.0.0"

[[trigger.http]]
route = "/api/orders/..."
component = "order-handler"

[component.order-handler]
source = "target/wasm32-wasi/release/order_handler.wasm"
[component.order-handler.build]
command = "cargo build --target wasm32-wasi --release"
```

```rust
// Rust ile HTTP handler
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[http_component]
fn handle_orders(req: Request) -> anyhow::Result<impl IntoResponse> {
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(r#"{"status": "ok"}"#)
        .build())
}
```

```bash
# Build ve push
spin build
spin registry push ghcr.io/company/order-api:v1.0

# Kubernetes'e deploy
spin kube deploy \
  --from ghcr.io/company/order-api:v1.0 \
  --runtime-class-name spin
```

---

## WASM + Knative (Serverless)

```yaml
# WASM workload'u Knative Service olarak çalıştır
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: wasm-function
  namespace: production
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: "0"    # Sıfıra in
        autoscaling.knative.dev/max-scale: "100"
    spec:
      runtimeClassName: wasmedge
      containers:
      - image: ghcr.io/company/wasm-function:v1.0
        resources:
          limits:
            memory: "16Mi"
```

---

## WASM for AI Inference (WasmEdge + ONNX)

```bash
# WasmEdge ile ONNX model çalıştırma
# Model: .onnx → WASM binary ile paketlenir

docker build -t ghcr.io/company/inference-wasm:v1.0 -f Dockerfile.wasm .
# Dockerfile.wasm:
#   FROM scratch
#   COPY model.onnx /model.onnx
#   COPY inference.wasm /inference.wasm
#   ENTRYPOINT ["/inference.wasm"]
```

---

## Mevcut Durum ve Sınırlamalar (2026)

```
✅ Olgun:
  - HTTP/gRPC microservice'ler
  - Edge proxy entegrasyonu
  - Plugin sistemleri (3rd party kod sandbox)
  - Serverless fonksiyonlar

⚠️  Gelişiyor:
  - WASI Preview 2 (network, filesystem erişimi)
  - Component Model (modüller arası bileşim)
  - GPU erişimi (WASI-NN ile sınırlı)

❌ Uygun Değil:
  - Stateful uygulamalar (DB, cache)
  - Uzun süre çalışan workload'lar
  - Tam Linux syscall gerektiren uygulamalar
```

> [!NOTE]
> WASM, container'ı tamamen değiştirmez — tamamlar. "Her şeyi WASM yap" değil, "uygun workload'ları WASM'a taşı" yaklaşımı 2026 gerçekçisidir.
