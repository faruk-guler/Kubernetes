# Runtime Güvenlik: Falco ve Trivy

## Runtime Güvenlik Nedir?

İmajları taradınız, RBAC ayarlarını yaptınız ve her şeyi kilitlediniz. Peki çalışan bir konteynerin içinde birisi aniden `/etc/shadow` dosyasına erişmeye çalışırsa ne olur? İşte burada **Runtime Security** devreye girer.

| Güvenlik Katmanı | Ne Zaman? | Araçlar |
|:---|:---:|:---|
| Statik tarama | Build sırasında | Trivy, Snyk |
| Admission | Deploy sırasında | Kyverno, OPA |
| **Runtime** | Çalışırken | **Falco**, Tetragon, **NeuVector** |

## Alternatif: NeuVector (Full-Lifecycle Security)
NeuVector, çalışan pod'lar arasındaki ağ trafiğini (L7) görselleştiren ve "Zero Trust" modelini otomatik uygulayan bir platformdur.
```bash
# NeuVector kurulumu (Helm)
helm repo add neuvector https://neuvector.github.io/neuvector-helm/
helm install neuvector neuvector/core --namespace neuvector --create-namespace
```

## Falco ile Tehdit Algılama

2026'da runtime güvenliğin tartışmasız standardı **Falco**'dur. Linux çekirdeğinden eBPF üzerinden gelen sinyalleri dinleyerek önceden tanımlanmış kurallara aykırı bir durum oluştuğunda uyarı verir.

```bash
# Falco kurulumu — eBPF sürücüsüyle (2026 standardı)
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set falcosidekick.enabled=true \
  --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/..."
```

## Falco Kuralları

```yaml
# Konteyner içinde terminal açılması
- rule: Terminal Shell in Container
  desc: A shell was spawned in a container with an attached terminal
  condition: >
    container.id != host
    and proc.name in (shell_procs)
    and proc.tty != 0
    and not container.image.repository in (trusted_images)
  output: >
    Shell spawned in container
    (user=%user.name container=%container.id image=%container.image.repository
    proc=%proc.name parent=%proc.pname)
  priority: WARNING
  tags: [container, shell, mitre_execution]

# /etc/passwd dosyasına yazma girişimi
- rule: Write to /etc/passwd
  desc: Detect writes to /etc/passwd
  condition: >
    open_write and fd.name=/etc/passwd
    and not proc.name in (passwd_binaries)
  output: >
    File /etc/passwd opened for writing (user=%user.name proc=%proc.name)
  priority: ERROR

# Dışa ağ bağlantısı (beklenmeyen)
- rule: Unexpected Outbound Connection
  desc: Detect unexpected outbound network connections
  condition: >
    outbound
    and not proc.name in (allowed_outbound_processes)
    and container
  output: >
    Unexpected outbound connection from container
    (user=%user.name proc=%proc.name container=%container.id
    ip=%fd.rip port=%fd.rport)
  priority: WARNING
```

## FalcoSidekick — Alert Yönlendirme

```yaml
# values.yaml
falcosidekick:
  enabled: true
  config:
    slack:
      webhookurl: "https://hooks.slack.com/services/..."
      minimumpriority: warning
    elasticsearch:
      hostport: "http://elasticsearch.monitoring:9200"
      index: falco-events
    webhook:
      address: "https://my-siem.example.com/events"
```

## Trivy Operator — Sürekli Güvenlik Taraması

2026'da imaj tarama sadece CI/CD'de değil, **cluster içinde sürekli** yapılır:

```bash
# Trivy Operator kurulumu
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set trivy.ignoreUnfixed=true

# Cluster genelinde güvenlik raporu
trivy k8s --report summary cluster

# Belirli namespace tarama
trivy k8s --report summary -n production
```

### Raporları Okuma

```bash
# Güvenlik açıkları
kubectl get vulnerabilityreport -A

# Konfigürasyon sorunları
kubectl get configauditreport -A

# Detaylı rapor
kubectl describe vulnerabilityreport <rapor-adı> -n production
```

> [!TIP]
> Falco + Trivy Operator kombinasyonu: Trivy konteyner imajlarını tarar; Falco ise çalışan konteynerde gerçek zamanlı şüpheli aktiviteleri yakalar. Her ikisi de 2026'da zorunlu kabul edilmektedir.
