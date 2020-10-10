#!/bin/bash

#dnf upgrade -y
dnf install -y \
    procps iproute iptables nftables \
    curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2 \
    git jq
curl -skL -o /tmp/crudini.noarch.rpm \
    https://cbs.centos.org/kojifiles/packages/crudini/0.9.3/1.el8/noarch/crudini-0.9.3-1.el8.noarch.rpm \
    && dnf localinstall -y /tmp/crudini.noarch.rpm \
    && rm -f /tmp/crudini.noarch.rpm

# podman
dnf install -y \
    podman podman-docker buildah     # crun slirp4netns varlink # systemd-container

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
# disable swap
sudo swapoff -a

# system
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/10-ip_forward.conf
echo 'net.ipv4.ip_unprivileged_port_start = 0' | sudo tee /etc/sysctl.d/11-unpriviledged_ports.conf
# Letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

crudini --set /etc/containers/registries.conf registries.insecure registries "['registry:5000']"

# ---- staging area ---- #
# user
su - vagrant -c "git config --global pull.ff only"
mkdir -p /usr/local/src
mkdir -p /usr/local/bin
chown -R vagrant: /usr/local/src

#pull kubeadm images
su - vagrant -c "kubeadm config images pull"

exit 0




#set cfg server address and access token enviroment variables
export cfgUSER="bootstrap"
export cfgURL="http://${cfgUser}@desktop.lan:8200"
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

