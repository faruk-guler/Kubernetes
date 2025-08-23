Now before we start the node we need to configure the token and master node api address. run bellow commands to create config folder and configure the master details.
```bash
mkdir -p /etc/rancher/rke2/
vim /etc/rancher/rke2/config.yaml
```
Content for config.yaml:
```bash
server: https://<server>:9345
token: <token from server node>
```
Replace the server from the real master server ip or hostname and replace the correct token.

# All these commands to run from master node.
### Local storage provisioner installation:
#### Dynamic storage provisioning
For the dynamic provisioning we need a storage class and rancher have the answer for this lab.

- Setup the provisioner
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml
``````
You can patch this storageClass to act as default
```bash
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```
Create a pvc and pod
```bash
kubectl create -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/examples/pvc/pvc.yaml
kubectl create -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/examples/pod/pod.yaml
```
### Cert manager installation:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

## Cluster Reset
RKE2 enables a feature to reset the cluster to one member cluster by passing ``--cluster-reset`` flag, when passing this flag to rke2 server it will reset the cluster with the same data dir in place, the data directory for etcd exists in ``/var/lib/rancher/rke2/server/db/etcd``, this flag can be passed in the events of quorum loss in the cluster.

To pass the reset flag, first you need to stop RKE2 service if its enabled via systemd:
```bash
systemctl stop rke2-server
rke2 server --cluster-reset
```
**Result:** A message in the logs say that RKE2 can be restarted without the flags. Start rke2 again and it should start rke2 as a 1 member cluster.
