# Cilium Hubble ile Ağ Gözlemlenebilirliği

## 2.1 Hubble Nedir?

Cilium eBPF kullandığı için ağ trafiğini en ince ayrıntısına kadar görebilir. **Hubble**, bu verileri görselleştirir ve sorgulanabilir hale getirir. Herhangi bir sidecar veya kod değişikliği gerektirmez.

## 2.2 Hubble Kurulumu

```bash
# Cilium kuruluysa Hubble'ı etkinleştir
cilium hubble enable --ui

# Hubble CLI kurulumu
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --fail --remote-name-all \
  https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz
tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin
rm hubble-linux-amd64.tar.gz

# Hubble durumunu doğrula
cilium hubble port-forward &
hubble status
```

## 2.3 Ağ Trafiği İzleme

```bash
# Belirli bir pod'un tüm trafiğini izle
hubble observe --pod production/my-app-pod -f

# HTTP trafiğini filtrele
hubble observe --protocol http --output flow -f

# Drop edilen paketleri gör (NetworkPolicy ihlalleri)
hubble observe --verdict DROPPED -f

# Belirli kaynak/hedef
hubble observe \
  --from-pod production/frontend \
  --to-pod production/backend \
  -f

# JSON formatında çıktı (SIEM entegrasyonu için)
hubble observe --output json | jq '.flow | {src: .source.pod_name, dst: .destination.pod_name, verdict: .verdict}'
```

## 2.4 Hubble UI

```bash
# Port yönlendirme ile UI'ya eriş
cilium hubble ui

# Veya manuel:
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# http://localhost:12000
```

Hubble UI'da görülen Service Map, pod'lar arasındaki tüm trafiği gerçek zamanlı olarak gösterir.

## 2.5 Hubble ile Güvenlik Denetimi

NetworkPolicy kurallarının doğru çalışıp çalışmadığını doğrulama:

```bash
# Hangi bağlantılar policy tarafından engelleniyor?
hubble observe --verdict DROPPED --namespace production -f

# Belirli bir policy'nin etkisini gör
hubble observe \
  --from-label app=frontend \
  --to-label app=database \
  --verdict DROPPED
```

## 2.6 Prometheus Entegrasyonu

Hubble metriklerini Prometheus'a aktarma:

```bash
cilium install \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"
```

Grafana dashboard ID: **16611** (Cilium/Hubble resmi dashboard)

> [!TIP]
> Hubble, "neden timeout alıyorum?" türündeki ağ sorunlarını çözmede SSH + tcpdump kombinasyonundan 10 kat daha hızlıdır. NetworkPolicy drop'larını, DNS başarısızlıklarını ve yavaş bağlantıları anlık olarak görebilirsiniz.

