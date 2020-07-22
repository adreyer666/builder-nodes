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
#    podman-docker
touch /etc/containers/nodocker

# cri-o
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo \
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_7/devel:kubic:libcontainers:stable.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.repo \
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.18/CentOS_7/devel:kubic:libcontainers:stable:cri-o:1.18.repo
dnf install -y cri-o
ln -s /bin/conmon /usr/libexec/crio
systemctl daemon-reload
systemctl start crio

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
    iproute-tc \
    kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
## # Set SELinux in permissive mode (effectively disabling it)
## setenforce 0
## sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# cleanup
dnf clean all


# ---- add some local configurations/tools ---- #
# system
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/10-ip_forward.conf
sysctl -p /etc/sysctl.d/10-ip_forward.conf
modprobe br_netfilter
cat > /etc/sysctl.d/k8s.conf <<EOM
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOM
sysctl --system
swapoff -a
if firewall-cmd --state; then
  firewall-cmd --permanent --add-port=6443/tcp
  firewall-cmd --permanent --add-port=2379-2380/tcp
  firewall-cmd --permanent --add-port=10250/tcp
  firewall-cmd --permanent --add-port=10251/tcp
  firewall-cmd --permanent --add-port=10252/tcp
  firewall-cmd --permanent --add-port=10255/tcp
  firewall-cmd –reload
fi

#mkdir -p /etc/containerd
#echo "plugins.cri.systemd_cgroup = true" >> /etc/containerd/config.toml

#mkdir -p /etc/docker
#cat > /etc/docker/daemon.json <<EOF
#{
#  "exec-opts": ["native.cgroupdriver=systemd"],
#  "log-driver": "json-file",
#  "log-opts": {
#    "max-size": "100m"
#  },
#  "storage-driver": "overlay2"
#}
#EOF

#mkdir -p /var/lib/kubelet
#cat > /var/lib/kubelet/config.yaml <<EOM
#apiVersion: kubelet.config.k8s.io/v1beta1
#kind: KubeletConfiguration
#cgroupDriver: systemd
#EOM

# ---- prepare control node ---- #
for ip in `hostname -I`; do
  case "$ip" in 192.168.121.*) echo "$ip node-cpmgr" | tee -a /etc/hosts;; esac
done
kubeadm config images pull


# ---- staging area ---- #
# user
su - vagrant -c "git config --global pull.ff only"
mkdir -p /usr/local/src
mkdir -p /usr/local/bin
chown -R vagrant: /usr/local/src

USERHOME=/home/vagrant
mkdir -p $USERHOME/.kube
touch $USERHOME/.kube/config
test -f /etc/kubernetes/admin.conf \
  && cp -av /etc/kubernetes/admin.conf $USERHOME/.kube/config
chown -R vagrant: $USERHOME/.kube
#su - vagrant -c 'kubeadm config images pull'
#su - vagrant -c 'kubeadm token list'


