## kubectl:
``` bash
An admin kubeconfig is generated at /etc/rancher/rke2/rke2.yaml.

Example:
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes
```
## Containerd:
``` bash
RKE2 ships with ctr and crictl. The Containerd socket is located at /run/k3s/containerd/containerd.sock.

Examples:
/var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io container ls

export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
/var/lib/rancher/rke2/bin/crictl ps

```
