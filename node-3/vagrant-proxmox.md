# vagrant-proxmox provider

## download to control panel server

```
wget 'https://releases.hashicorp.com/vagrant/2.2.9/vagrant_2.2.9_x86_64.deb'
wget https://github.com/lehn-etracker/vagrant-proxmox/releases/download/v0.3.0/vagrant-proxmox-0.3.0.gem
apt install ./vagrant_2.2.9_x86_64.deb
dpkg -l vagrant
vagrant plugin list
vagrant plugin install ./vagrant-proxmox-0.3.0.gem
vagrant plugin list
```

## boxes
```
vagrant box list
vagrant box add centos/8
ls -la ~/.vagrant.d/boxes
```

## Proxmox
Commandline tools:
* `pvesh` - access to API from shell
* `qm` - Qemu/KVM Virtual Machine Manager
* `pct` - tool to manage Linux Containers (LXC)


### import a qcow2 file for templating
An openvz template or iso image with vagrant user setup is mandatory..

```
node_name=pve
name=centos-8
image=/tmp/${name}.qcow2
scp  ~/.vagrant.d/boxes/centos-*-8/*/libvirt/box.img ${node_name}:${image}
```

#### proxmox - import disk to new image
```
name=centos-8
image=/tmp/${name}.qcow2

# Get a vmid
vmid=`pvesh get /cluster/nextid | sed -e 's/"//g'`
# create new vm
qm create ${vmid} --bootdisk scsi0 -name ${name}
# import the disk
qm importdisk ${vmid} ${image} local-lvm
# set the imported disk as bootdisk
qm set ${vmid} --scsi0 local-lvm:vm-${vmid}-disk-0
# ensure all disk (and disk sizes) are accounted for
qm rescan
# cleanup
rm -f ${image}
```

#### Convert vm to template
```
qm template ${vmid}
```

#### proxmox create vm via API
```
# Get a vmid
vmid=`pvesh get /cluster/nextid | sed -e 's/"//g'`
# Create a disk image
# {your node name} should be replaced by something from the output of: pvesh get /nodes | grep '"node" :'
pvesh create /nodes/${node_name}/storage/local/content -filename vm-$vmid-disk-1.qcow2 -size 20G -vmid $vmid
# That image can't be assigned from the web interface (I think that's a bug or I missed something)
# Create a machine from command line and assign the image to it.
pvesh create /nodes/${node_name}/qemu -memory 2048 -sockets 1 -cores 2 -net0 e1000,bridge=vmbr0 -vmid $vmid -ostype l26 -sata0 media=disk,volume=local:$vmid/vm-$vmid-disk-1.qcow2
```

#### proxmox - create container from physical machine backup
```
cd /
tar -cvpzf backup.tar.gz --exclude=/backup.tar.gz /

# Get a vmid
vmid=`pvesh get /cluster/nextid | sed -e 's/"//g'`
# create new vm
pct create ${vmid} local:vztmpl/backup.tar.gz -hostname $hostname -onboot 1 -rootfs local-lvm:20 -memory 2048 -cores 2
```

## Run Vagrant with proxmox provider
The `proxmox` API by default runs on port 8006 and is only available via https using self signed certificates. If you cannot get an "official" certificate (eg. from letsencrypt), then you can either:
- add the proxmox PVE's pve-root-ca.pem file to the vagrant CA cert chain. This allows Vagrant to run its SSL check properly and trust the self signed cert provided by Proxmox.
  - `(echo "Proxmox server"; cat pve-root-ca.pem ) >> ~/.vagrant.d/gems/gems/excon-*/data/cacert.pem`
- modify the provider to not verify the SSL certificate (verify_ssl: false)


## Links
* https://www.gastongonzalez.com/tech-blog/2016/12/24/building-a-developer-virtualization-lab-part-2


