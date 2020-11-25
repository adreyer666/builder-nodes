#!/bin/bash

set -e

#sudo dnf upgrade -y
sudo dnf install -y \
    procps iproute iptables nftables \
    lsof psmisc curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2 jq

#-----------------------------------------------------------

configure_system(){
  # Set SELinux in permissive mode (effectively disabling it)
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

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
}

install_podman() {
  OS="CentOS_8_Stream"
  # podman buildah tc    # crun slirp4netns varlink # systemd-container podman-docker
  sudo dnf -y module disable container-tools
  sudo dnf -y install 'dnf-command(copr)'
  sudo dnf -y copr enable rhcontainerbot/container-selinux
  sudo curl -sL -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/${OS}/devel:kubic:libcontainers:stable.repo
  sudo dnf -y install libseccomp podman

  sudo mkdir -p /etc/containers
  sudo touch /etc/containers/nodocker
}

install_crio() {
  OS="CentOS_8_Stream"
  criover="1.19"
  # CRI-O
  sudo curl -sL -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/${OS}/devel:kubic:libcontainers:stable.repo
  sudo curl -sL -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${criover}/${OS}/devel:kubic:libcontainers:stable:cri-o:${criover}.repo
  sudo dnf install -y conntrack-tools cri-o
  sudo systemctl daemon-reload
  sudo systemctl start crio
}

runasuser() {
  su - vagrant -c "$*"
}

install_minikube() {
  # minikube
  curl -sLO https://storage.googleapis.com/minikube/releases/latest/minikube-latest.x86_64.rpm
  sudo rpm -ivh minikube-latest.x86_64.rpm
  test \! -f /usr/bin/kubectl \
    && printf '#!/bin/sh -f\nexec /usr/bin/minikube kubectl -- "$@"\n' | sudo tee /usr/bin/kubectl \
    && sudo chmod 755 /usr/bin/kubectl

  echo "export MINIKUBE_IN_STYLE=false" | runasuser tee -a .bashrc
  runasuser minikube config set memory 1989
  runasuser minikube config set driver podman
  runasuser minikube config set container-runtime cri-o
  runasuser minikube start
  runasuser minikube version
  runasuser minikube stop

  sudo tee /etc/systemd/system/minikube.service <<EOF
[Unit]
Description=Minikube startup

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="MINIKUBE_IN_STYLE=false"
ExecStart=/usr/bin/minikube start
ExecStop=/usr/bin/minikube stop
User=vagrant
Group=vagrant

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now minikube
  sudo systemctl restart minikube

  # enable modules
  runasuser minikube addons enable dashboard
  runasuser minikube addons enable metrics-server
  runasuser kubectl get pod,svc -n kube-system
  runasuser kubectl config view

  # allow connections to dashboard
  runasuser kubectl proxy --address 0.0.0.0 --disable-filter=true & disown
  sudo iptables -A INPUT -p tcp -s 192.168.121.0/24 --dport 8001 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 8001 -j REJECT

  ip=`hostname -I | cut -d\  -f1`
  dpath='/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/'
  echo "Dashboard is available at: http://${ip}:8001${dpath}"
  # security token
  runasuser kubectl -n kube-system describe $(runasuser kubectl -n kube-system get secret -n kube-system -o name | grep namespace) | grep token:
}

test_minikube() {
  runasuser kubectl create deployment hello-minikube --image=k8s.gcr.io/echoserver:1.4
  sleep 15
  runasuser kubectl get deployments
  runasuser kubectl get pods
  runasuser kubectl get events

  runasuser kubectl expose deployment hello-minikube --type=NodePort --port=8080
  sleep 10
  runasuser kubectl get services hello-minikube
  runasuser minikube service hello-minikube
  runasuser kubectl port-forward --address 0.0.0.0 service/hello-minikube 7080:8080 &
  pid=$!
  sleep 2
  ip=`hostname -I | cut -d\  -f1`
  echo "Test app is available at: http://${ip}:7080"
  echo -n "press enter to stop "; read x

  # cleanup
  runasuser kill ${pid}
  runasuser kubectl delete service hello-minikube
  runasuser kubectl delete deployment hello-minikube

  #---------------------------

  runasuser kubectl create deployment balanced --image=k8s.gcr.io/echoserver:1.4
  runasuser kubectl expose deployment balanced --type=LoadBalancer --port=8080
  runasuser minikube tunnel -c &
  pid=$!
  runasuser kubectl get services balanced
  ip=`runasuser kubectl get services balanced -o json | jq -r .spec.clusterIP`
  echo "Test app is available at http://${ip}:8080"
  echo '----------------'
  curl http://${ip}:8080
  echo '----------------'

  # cleanup
  runasuser kill ${pid}
  runasuser kubectl delete service balanced
  runasuser kubectl delete deployment balanced

  #---------------------------

  runasuser kubectl get svc,pods,deploy -A
}

#-----------------------------------------------------------

configure_system
install_podman
install_crio
install_minikube
sudo dnf clean all     # cleanup

exit 0

