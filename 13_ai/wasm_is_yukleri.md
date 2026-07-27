# WebAssembly (WASM) İş Yükleri

Kubernetes üzerinde bugüne kadar hep standart Linux konteynerlerini çalıştırdık. Ancak 2026 yılı itibarıyla, konteynerlere alternatif veya onları tamamlayıcı çok daha hafif, hızlı başlayan ve donanım bağımsız çalışan yeni bir teknoloji olgunluğa ulaşmıştır: **WebAssembly (WASM)**.

WASM, tarayıcıların dışında sunucu tarafında da çalışabilen, milisaniyelerin altında başlayan ve megabaytlar yerine kilobaytlar seviyesinde yer kaplayan yeni nesil bir çalışma formatıdır.

---

## 1. Karşılaştırma: WASM vs. Konteyner (Container)

| Özellik | Standart Container (OCI) | WebAssembly (WASM) |
|:--------|:------------------------|:-------------------|
| **Başlatma Süresi** | ~100ms - Birkaç saniye | < 1ms (Mikrosaniyeler düzeyinde) |
| **Bellek Tüketimi** | Megabaytlar - Gigabaytlar | Kilobaytlar - Megabaytlar |
| **İşletim Sistemi Bağımlılığı**| Var (Linux kernel namespace gerekir) | Yok (WASI sandbox ile izole çalışır) |
| **Taşınabilirlik** | Sadece derlendiği CPU mimarisinde | Donanımdan tamamen bağımsız (Her yerde çalışır) |
| **Güvenlik İzolasyonu** | Cgroups ve Namespaces | Capability-based Sandbox |

---

## 2. containerd ve runwasi Entegrasyonu

Kubernetes düğümlerinin (nodes) içindeki `containerd` çalışma zamanı, standart olarak Linux konteynerlerini (`runc` ile) yönetir. WebAssembly ikililerini (.wasm) çalıştırabilmek için, containerd'ye **runwasi** (containerd'nin WASM shim projeleri) entegre edilmelidir.

```
[ Pod Talebi ] ──► [ Kubelet ] ──► [ containerd ]
                                          │
                                          ├─► runc (Linux Containers)
                                          └─► runwasi (WebAssembly Shim)
```

### Adım 1: containerd Yapılandırması (`/etc/containerd/config.toml`)

 container çalışma zamanında WASM motorlarını (Örn: Spin veya WasmEdge) aktifleştirmek için `config.toml` dosyasına şu runwasi shim tanımları eklenir:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.wasmedge]
  runtime_type = "io.containerd.wasmedge.v1"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.spin]
  runtime_type = "io.containerd.spin.v2"
```

*Yapılandırmanın ardından `sudo systemctl restart containerd` komutuyla servis yeniden başlatılır.*

---

## 3. Kubernetes RuntimeClass Tanımı

Kubernetes API sunucusuna, gelen podların hangi WASM runtime'ını kullanacağını bildiren `RuntimeClass` nesneleri oluşturulmalıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [wasm_is_yukleri_manifest_1.yaml](../Manifests/12_ai/wasm_is_yukleri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. WASM Pod Dağıtımı (Deployment)

Oluşturduğumuz `RuntimeClass` ile bir WASM uygulamasını Kubernetes üzerinde ayağa kaldırmak oldukça basittir. Pod tanımına sadece `runtimeClassName` eklememiz yeterlidir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [wasm_is_yukleri_manifest_2.yaml](../Manifests/12_ai/wasm_is_yukleri_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Spin Framework (Rust ile HTTP Mikroservis)

WASM mikroservisleri geliştirmek için en popüler araçlardan biri Fermyon tarafından geliştirilen **Spin** kütüphanesidir.

### Rust Kod Tanımı (`src/lib.rs`)

```rust
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[http_component]
fn handle_hello(req: Request) -> anyhow::Result<impl IntoResponse> {
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(r#"{"status": "WASM on Kubernetes is Active!"}"#)
        .build())
}
```

### Spin Proje Yapılandırması (`spin.toml`)

```toml
spin_manifest_version = 2

[application]
name = "k8s-hello-wasm"
version = "1.0.0"

[[trigger.http]]
route = "/hello"
component = "hello-handler"

[component.hello-handler]
source = "target/wasm32-wasi/release/k8s_hello_wasm.wasm"
[component.hello-handler.build]
command = "cargo build --target wasm32-wasi --release"
```

### Kubernetes'e Dağıtım

Spin CLI aracılığıyla projeyi doğrudan derleyip Kubernetes'e deploy edebilirsiniz:

```bash
# Derle ve OCI registry'e push et
spin build
spin registry push ghcr.io/my-company/k8s-hello-wasm:v1.0

# Kubernetes'e deploy et
spin kube deploy \
  --from ghcr.io/my-company/k8s-hello-wasm:v1.0 \
  --runtime-class-name wasm-spin
```

---

## 6. WASM + Knative (Serverless Entegrasyonu)

WebAssembly'nin uyanma süresi 1 milisaniyenin altında olduğu için, serverless (Knative) mimarileriyle mükemmel uyumludur. Geleneksel konteynerlerdeki 0'dan uyanma (cold-start) gecikmesi WASM ile tamamen yok olur.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [wasm_is_yukleri_manifest_3.yaml](../Manifests/12_ai/wasm_is_yukleri_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. 2026 WASM Durumu ve Sınırları

```
✅ Mükemmel Olduğu Alanlar:
  - HTTP/gRPC mikroservisleri ve API sunucuları.
  - Serverless / FaaS (Function as a Service) iş yükleri.
  - Cold-start süresinin hayati olduğu durumlar.
  - Edge computing (Düşük donanımlı küçük sensörler, kasalar).

⚠️ Gelişmekte Olan / Sınırlı Alanlar:
  - GPU Erişimi (WASI-NN standardı ile sınırlı olarak desteklenir).
  - Dosya sistemi (file system) ve karmaşık ağ erişimleri (WASI Preview 2 ile çözülmektedir).

❌ Uygun Olmayan Alanlar:
  - Stateful / Durumlu veritabanları (PostgreSQL, Redis vb.).
  - Doğrudan Linux sistem çağrısı (syscall) gerektiren altyapı araçları.
```

---

## 8. Özet

WebAssembly, konteynerleri tamamen ortadan kaldırmaz; aksine hafif ve anlık çalışması gereken mikroservis iş yükleri için onları mükemmel bir şekilde tamamlar. 2026 yılı itibarıyla Kubernetes üzerinde runwasi shim katmanları sayesinde konteynerler ile WASM podları yan yana, tam bir uyum içinde çalışmaktadır.
