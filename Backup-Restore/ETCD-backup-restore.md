### ETCD backup restore
- Creating Snapshots   

Snapshots are enabled by default.

The snapshot directory defaults to ``/var/lib/rancher/rke2/server/db/snapshots.``   
In RKE2, snapshots are stored on each etcd node. If you have multiple etcd or etcd + control-plane nodes, you will have multiple copies of local etcd snapshots.

You can take a snapshot manually while RKE2 is running with the etcd-snapshot subcommand. For example: ``rke2 etcd-snapshot save --name pre-upgrade-snapshot.``

