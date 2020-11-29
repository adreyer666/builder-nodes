# builder-nodes

## Desired Kubernetes setup
* Networking set up
* Kubernetes dashboard running and available to be accessed from outside the kubernetes environment.


## Kubernetes recipes

* [minikube](./minikube) - single host kubernetes setup (working)
* [k3s](./k3s) - clustered setup with provision for 1 master and 2 worker nodes (working)
* [cluster-1](./cluster-1) - kubernetes setup with 1 master/2 worker (not working/work in progress)
* [cluster-2](./cluster-2) - kubernetes setup with 1 master/2 worker (not working/work in progress)
* [test-nodes](./test-nodes) - early tests with the kubernetes setup (not working)


## TODO
* set up environment with [Packer](https://www.packer.io/downloads.html) utilizing [Ansible]() as [provisioner]() to build my own base images for vagrant. [1](https://github.com/vagrant-libvirt/vagrant-libvirt#create-box)
* when using libvirt as virtualization backend make sure to set up the channels for `guest_agent`/`spice` access. [1](https://libvirt.org/formatdomain.html#elementCharChannel), see node-2 for example

