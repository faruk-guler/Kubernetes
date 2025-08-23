### ETCD backup restore
- Creating Snapshots   

Snapshots are enabled by default.

The snapshot directory defaults to ``/var/lib/rancher/rke2/server/db/snapshots.``   
In RKE2, snapshots are stored on each etcd node. If you have multiple etcd or etcd + control-plane nodes, you will have multiple copies of local etcd snapshots.

You can take a snapshot manually while RKE2 is running with the etcd-snapshot subcommand. For example: ``rke2 etcd-snapshot save --name pre-upgrade-snapshot.``

### Restoring a Snapshot to Existing Nodes
When RKE2 is restored from backup, the old data directory will be moved to /var/lib/rancher/rke2/server/db/etcd-old-%date%/. RKE2 will then attempt to restore the snapshot by creating a new data directory and start etcd with a new RKE2 cluster with one etcd member.

You must stop RKE2 service on all server nodes if it is enabled via systemd. Use the following command to do so:
```bash
systemctl stop rke2-server
```

Next, you will initiate the restore from snapshot on the first server node with the following commands:
```bash
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=<PATH-TO-SNAPSHOT>
```
Once the restore process is complete, start the rke2-server service on the first server node as follows:
```bash
systemctl start rke2-server
```
Remove the rke2 db directory on the other server nodes as follows:
```bash
rm -rf /var/lib/rancher/rke2/server/db
```
Start the rke2-server service on other server nodes with the following command:
```bash
systemctl start rke2-server
```
**Result:** After a successful restore, a message in the logs says that etcd is running, and RKE2 can be restarted without the flags. Start RKE2 again, and it should run successfully and be restored from the specified snapshot.

When rke2 resets the cluster, it creates an empty file at ``/var/lib/rancher/rke2/server/db/reset-flag.`` This file is harmless to leave in place, but must be removed in order to perform subsequent resets or restores. This file is deleted when rke2 starts normally.

