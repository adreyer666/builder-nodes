# Kubernetes (k8s) setup

Random notes..

## Install kubernetes nodes
* Ref: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

### Debian
```
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### Centos
```
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i --follow-symlinks 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
```

#### open firewalld ports
* Ref: https://www.tecmint.com/install-a-kubernetes-cluster-on-centos-8/

```
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10251/tcp
firewall-cmd --permanent --add-port=10252/tcp
firewall-cmd --permanent --add-port=10255/tcp
firewall-cmd –reload
modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
```


## Configure kubernetes

### create cluster
* Ref: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/

```
PODNET="10.85.0.0/16"
for ip in `hostname -I`; do
  case "$ip" in 192.168.121.*) echo "$ip node-cpmgr" | sudo tee -a /etc/hosts;; esac
done
kubeadm config images pull
kubeadm init \
    --control-plane-endpoint node-cpmgr \
    --pod-network-cidr=${PODNET}
# pod-network provider
kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml
kubeadm token list

# TOKEN=$(sudo kubeadm token generate); echo ${TOKEN}
# kubeadm init --token=${TOKEN} --kubernetes-version=${VERSION} \

```

### allow user (non-root) access
As user run:

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

