#!/bin/sh -f

DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND

apt-get update -q
apt-get upgrade -q -y
apt-get dist-upgrade -q -y

apt-get install -q -y --no-install-recommends \
    procps iproute2 iptables nftables \
    curl ca-certificates sudo \
    vim-tiny openssh-client gpg gpg-agent lrzip \
    git

# podman
echo 'deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_Testing/ /' > /etc/apt/sources.list.d/libcontainers.list
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_Testing/Release.key | apt-key add -
apt-get update -q
apt-get install -q -y --no-install-recommends \
    podman-rootless buildah runc umoci slirp4netns

# kubernetes
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-get install -q -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# cleanup
apt-get install -f
apt-get clean && rm -rf /tmp/* /var/lib/apt/lists/* /var/cache/apt/archives/partial


# ---- add some local configurations/tools ---- #
# activate user namespaces
echo "kernel.unprivileged_userns_clone=1" >> /etc/sysctl.d/10-userns.conf
sysctl -p /etc/sysctl.d/10-userns.conf
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


