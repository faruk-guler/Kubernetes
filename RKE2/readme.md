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
