#!/bin/sh -f

#dnf upgrade -y
dnf install -y \
    procps iproute iptables nftables \
    curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2 \
    git

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
sysctl -p /etc/sysctl.d/10-ip_forward.conf
cat > /etc/sysctl.d/k8s.conf <<EOM
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOM
sysctl --system
swapoff -a

# ---- staging area ---- #
# user
su - vagrant -c "git config --global pull.ff only"
mkdir -p /usr/local/src
mkdir -p /usr/local/bin
chown -R vagrant: /usr/local/src


