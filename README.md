# builder-nodes

## System setup

All nodes are set up using `vagrant`.
* `node-\d` are Worker nodes. Adjust the `Vagrantfile` with your access credentials to your `libvirt` server  or `proxmox` cluster.
* `node-cn` is a Control Plane node.


### Docker / Podman
Ensure you have all upstream registries in the registry list. When starting to create your own containers you might want to spin up your own registry and add it as well.

```
# cat /etc/containers/registries.conf
[registries.search]
registries = ['docker.io', 'quay.io', 'registry.fedoraproject.org', 'registry.access.redhat.com']
```


