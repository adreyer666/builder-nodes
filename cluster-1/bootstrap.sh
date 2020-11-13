#!/bin/bash

#dnf upgrade -y
sudo dnf install -y \
    procps iproute iptables nftables \
    curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2 \
    git jq \
    nfs-utils

CFG=/vagrant/kcluster-config.json
crudver=`jq -r .sw.crudini.version < ${CFG}`
crudrev=`jq -r .sw.crudini.revision < ${CFG}`
criover=`jq -r .sw.crio.version < ${CFG}`
crioos=`jq -r .sw.crio.os < ${CFG}`
kubeos=`jq -r .sw.kube.os < ${CFG}`

curl -skL -o /tmp/crudini.noarch.rpm \
    https://cbs.centos.org/kojifiles/packages/crudini/${crudver}/1.el8/noarch/crudini-${crudver}-${crudrev}.noarch.rpm \
    && sudo dnf localinstall -y /tmp/crudini.noarch.rpm \
    && rm -f /tmp/crudini.noarch.rpm

# podman
sudo dnf install -y \
    podman podman-docker buildah tc    # crun slirp4netns varlink # systemd-container

# kubernetes
sudo tee /etc/yum.repos.d/kubernetes.repo <<EOM
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-${kubeos}-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
sudo dnf install -y \
    --disableexcludes=kubernetes \
    kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# cleanup
sudo dnf clean all


# ---- add some local configurations/tools ---- #
# disable swap
sudo swapoff -a

# system
sudo modprobe -v overlay
sudo modprobe -v br_netfilter
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/10-ip_forward.conf
echo 'net.ipv4.ip_unprivileged_port_start = 0' | sudo tee /etc/sysctl.d/11-unpriviledged_ports.conf
# Letting iptables see bridged traffic
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system
sudo touch /etc/containers/nodocker

sudo crudini --set /etc/containers/registries.conf registries.insecure registries "['registry:5000']"

# CRI-O
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/${crioos}/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${criover}/${crioos}/devel:kubic:libcontainers:stable:cri-o:${criover}.repo
sudo dnf install -y cri-o
sudo systemctl daemon-reload
sudo systemctl start crio


#sudo crudini --set /etc/containerd/config.toml plugins.cri systemd_cgroup "true"


# ---- staging area ---- #
# user
su - vagrant -c "git config --global pull.ff only"
mkdir -p /usr/local/src
mkdir -p /usr/local/bin
chown -R vagrant: /usr/local/src

#pull kubeadm images
su - vagrant -c "kubeadm config images pull"

exit 0


#----------------------------------------------------------------------------------------#


#set cfg server address and access token enviroment variables
export cfgURL="http://bootstrap@desktop.lan:8200"
export TOKEN="nvfkivgewrjgtoirewnh"
# CA
curl -skL --oauth2-bearer "${TOKEN}" ${cfgURL}/pki_int/issue/leaf-cert/kubernetes > ca.json
cat ca.json | jq -r .data.certificate > ca-cert.pem
cat ca.json | jq -r .data.issuing_ca > ca.pem
cat ca.json | jq -r .data.private_key > ca-key.pem
rm ca.json
# Admin
curl -skL --oauth2-bearer "${TOKEN}" ${cfgURL}/pki_int/issue/leaf-cert/admin > admin.json
cat admin.json | jq -r .data.certificate > admin.pem
cat admin.json | jq -r .data.private_key > admin-key.pem
rm admin.json
# Nodes
NODES=4
for (( S=0; S<=$NODES; S++ )); do
  curl -skL --oauth2-bearer "${TOKEN}" ${cfgURL}/pki_int/issue/leaf-cert/node$S > node$S.json
  cat node$S.json | jq -r .data.certificate > node$S.pem
  cat node$S.json | jq -r .data.private_key > node$S-key.pem
  rm node$S.json
done

