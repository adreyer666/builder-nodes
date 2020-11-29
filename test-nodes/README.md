# test-nodes

## System setup

All nodes are set up using `vagrant`.
* `node-\d` are Worker nodes. Adjust the `Vagrantfile` with your access credentials to your `libvirt` server  or `proxmox` cluster.
* `node-cn` is a Control Plane node.


### Docker / Podman
Ensure you have all upstream registries in the registry list. When starting to create your own containers you *do* want to spin up your own registry and add it to the list.

```
# cat /etc/containers/registries.conf
[registries.search]
registries = ['docker.io', 'quay.io', 'registry.fedoraproject.org', 'registry.access.redhat.com']
```


## Management
```
$ sudo apt install terminator
$ cp terminator.config ~/.config/terminator/config
$ terminator -l pods
```

## TODO
* set up environment with [Packer](https://www.packer.io/downloads.html) utilizing [Ansible]() as [provisioner]() to build my own base images for vagrant. [1](https://github.com/vagrant-libvirt/vagrant-libvirt#create-box)
* when using libvirt as virtualization backend make sure to set up the channels for `guest_agent`/`spice` access. [1](https://libvirt.org/formatdomain.html#elementCharChannel), see node-2 for example

