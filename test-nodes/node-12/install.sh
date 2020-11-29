#!/bin/sh -f

#dnf upgrade -y
dnf install -y \
    procps iproute iptables nftables \
    curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2 \
    git
curl -skL -o /tmp/crudini.noarch.rpm \
    https://cbs.centos.org/kojifiles/packages/crudini/0.9.3/1.el8/noarch/crudini-0.9.3-1.el8.noarch.rpm \
    && dnf localinstall -y /tmp/crudini.noarch.rpm \
    && rm -f /tmp/crudini.noarch.rpm

# podman
dnf install -y \
    podman buildah

# kubernetes
cat > /etc/yum.repos.d/kubernetes.repo <<EOM
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
dnf install -y \
    --disableexcludes=kubernetes \
    kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# cleanup
dnf clean all


# ---- add some local configurations/tools ---- #
# system
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/10-ip_forward.conf
echo 'net.ipv4.ip_unprivileged_port_start = 0' > /etc/sysctl.d/11-unpriviledged_ports.conf
cat > /etc/sysctl.d/k8s.conf <<EOM
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOM
sysctl --system
swapoff -a

crudini --set /etc/containers/registries.conf registries.insecure registries "['registry:5000']"

# ---- staging area ---- #
# user
su - vagrant -c "git config --global pull.ff only"
mkdir -p /usr/local/src
mkdir -p /usr/local/bin
chown -R vagrant: /usr/local/src


