## Cluster Reset
RKE2 enables a feature to reset the cluster to one member cluster by passing ``--cluster-reset`` flag, when passing this flag to rke2 server it will reset the cluster with the same data dir in place, the data directory for etcd exists in ``/var/lib/rancher/rke2/server/db/etcd``, this flag can be passed in the events of quorum loss in the cluster.

To pass the reset flag, first you need to stop RKE2 service if its enabled via systemd:
```bash
systemctl stop rke2-server
rke2 server --cluster-reset
```
**Result:** A message in the logs say that RKE2 can be restarted without the flags. Start rke2 again and it should start rke2 as a 1 member cluster.
