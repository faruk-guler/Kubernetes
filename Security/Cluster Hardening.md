# Cluster Hardening ve Security Audit

Bu bÃ¶lÃ¼mde cluster'Ä±nÄ±zÄ± gerÃ§ek dÃ¼nya saldÄ±rÄ±larÄ±na karÅŸÄ± nasÄ±l sertleÅŸtireceÄŸinizi (hardening) Ã¶ÄŸreneceÄŸiz.

## CIS Benchmark ile Denetim

Center for Internet Security (CIS), Kubernetes iÃ§in yÃ¼zlerce maddelik bir gÃ¼venlik kontrol listesi sunar.

```bash
# kube-bench ile CIS denetimi
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# SonuÃ§larÄ± gÃ¶r
kubectl logs job.batch/kube-bench

# Sadece baÅŸarÄ±sÄ±z testler
kubectl logs job.batch/kube-bench | grep -E 'FAIL|WARN'
```

## API Server Hardening

```yaml
# kubeadm yapÄ±landÄ±rmasÄ±
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  extraArgs:
    anonymous-auth: "false"                    # Anonim eriÅŸim kapat
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-log-maxage: "30"
    audit-log-maxbackup: "10"
    audit-log-maxsize: "100"
    enable-admission-plugins: "NodeRestriction,AlwaysPullImages"
    encryption-provider-config: "/etc/kubernetes/encryption-config.yaml"
```

### etcd Ã…Âifreleme

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <BASE64_32_BYTE_KEY>
  - identity: {}   # Fallback (ÅŸifresiz okuma iÃ§in)
```

## Node ve Konteyner Hardening

Her pod iÃ§in zorunlu hale getirilmesi gereken `securityContext`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true               # Root dÄ±ÅŸÄ± kullanÄ±cÄ±
        seccompProfile:
          type: RuntimeDefault           # Sistem Ã§aÄŸrÄ±sÄ± filtresi
      containers:
      - name: app
        image: my-app:v1.0.0
        securityContext:
          runAsUser: 1000                # Belirli kullanÄ±cÄ± ID
          runAsGroup: 3000
          readOnlyRootFilesystem: true   # Dosya sistemi sadece okunabilir
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL                        # TÃ¼m Linux yeteneklerini kaldÄ±r
            add:
            - NET_BIND_SERVICE           # Sadece gerekli olanÄ± ekle
```

## Temel Hardening AdÄ±mlarÄ±

### Node GÃ¼venliÄŸi
```bash
# SSH sadece jump-host Ã¼zerinden
# /etc/ssh/sshd_config
PasswordAuthentication no
AllowUsers admin
AllowGroups sre-team
```

### etcd GÃ¼venliÄŸi

```bash
# etcd sadece localhost ve TLS ile dinlemelidir
# etcd flags:
--listen-client-urls=https://127.0.0.1:2379
--advertise-client-urls=https://127.0.0.1:2379
--cert-file=/etc/kubernetes/pki/etcd/server.crt
--key-file=/etc/kubernetes/pki/etcd/server.key
--peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
--client-cert-auth=true
```

### Kontrol Listesi

```bash
# 1. Anonymous auth kapalÄ± mÄ±?
curl -k https://<API_SERVER>:6443/api --header "Authorization: Bearer bad-token"
# 401 dÃ¶nmeli

# 2. etcd dÄ±ÅŸarÄ±ya aÃ§Ä±k mÄ±? (boÅŸ dÃ¶nmeli)
nmap -p 2379 <NODE_IP>

# 3. Pod'lar root mu Ã§alÄ±ÅŸÄ±yor?
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].securityContext.runAsUser}{"\n"}{end}'

# 4. Privileged pod var mÄ±?
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].securityContext.privileged}{"\n"}{end}'
```

## Trivy ile Cluster Denetimi

```bash
# Tam cluster gÃ¼venlik raporu
trivy k8s --report summary cluster

# Sadece yÃ¼ksek/kritik aÃ§Ä±klar
trivy k8s --severity HIGH,CRITICAL --report all cluster
```

> [!CAUTION]
> Cluster hardening adÄ±mlarÄ±nÄ± production'a uygulamadan Ã¶nce mutlaka test ortamÄ±nda deneyin. `--anonymous-auth=false` veya yanlÄ±ÅŸ audit policy bazÄ± sistem bileÅŸenlerini kÄ±rabilir.
