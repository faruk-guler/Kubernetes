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
