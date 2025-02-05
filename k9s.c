Default Kubectl yapılandıransını K9s otomatik olarak kullanır. 

#Kısaltmalar:
csr: certificatesigningrequests
cs: componentstatuses
cm: configmaps
ds: daemonsets
deploy: deployments
ep: endpoints
ev: events
hpa: horizontalpodautoscalers
ing: ingresses
limits: limitranges
ns: namespaces
no: nodes
pvc: persistentvolumeclaims
pv: persistentvolumes
po: pods
pdb: poddisruptionbudgets
psp: podsecuritypolicies
rs: replicasets
rc: replicationcontrollers
quota: resourcequotas
sa: serviceaccounts
svc: services


# List current version
k9s version

# To get info about K9s runtime (logs, configs, etc..)
k9s info

# List all available CLI options
k9s help

# To run K9s in a given namespace
k9s -n mycoolns

# Start K9s in an existing KubeConfig context
k9s --context coolCtx

# Start K9s in readonly mode - with all cluster modification commands disabled
k9s --readonly
