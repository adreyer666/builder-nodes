#!/bin/bash

#sudo dnf upgrade -y
sudo dnf install -y \
    procps iproute iptables nftables \
    lsof psmisc curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2

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

install_minikube() {
  # minikube
  curl -sLO https://storage.googleapis.com/minikube/releases/latest/minikube-latest.x86_64.rpm
  sudo rpm -ivh minikube-latest.x86_64.rpm

  minikube config set memory 1989
  minikube config set driver podman
  minikube config set container-runtime cri-o
  minikube start
  minikube version

  test \! -f /usr/bin/kubectl \
    && printf '#!/bin/sh -f\nexec /usr/bin/minikube kubectl -- "$@"\n' | sudo tee /usr/bin/kubectl \
    && sudo chmod 755 /usr/bin/kubectl

  sudo tee /etc/systemd/system/minikube.service <<EOF
[Unit]
Description=Minikube startup

[Service]
Type=oneshot
RemainAfterExit=yes
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
  minikube addons enable metrics-server
  kubectl get pod,svc -n kube-system
  kubectl config view

  # allow connections to dashboard
  kubectl proxy --address 0.0.0.0 --disable-filter=true & disown
  sudo iptables -A INPUT -p tcp -s 192.168.121.0/24 --dport 8001 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 8001 -j REJECT

  ip=`hostname -I | cut -d\  -f1`
  dpath='/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/'
  echo "Dashboard is available at: http://${ip}:8001${dpath}"
  # security token
  kubectl -n kube-system describe $(kubectl -n kube-system get secret -n kube-system -o name | grep namespace) | grep token:
}

test_minikube() {
  kubectl create deployment hello-minikube --image=k8s.gcr.io/echoserver:1.4
  sleep 15
  kubectl get deployments
  kubectl get pods
  kubectl get events


  ## kubectl expose deployment hello-minikube --type=LoadBalancer --port=8080
  ## minikube service hello-minikube
  ## kubectl get services

  kubectl expose deployment hello-minikube --type=NodePort --port=8080
  sleep 10
  kubectl get services hello-minikube
  minikube service hello-minikube
  kubectl port-forward --address 0.0.0.0 service/hello-minikube 7080:8080 &
  sleep 2
  ip=`hostname -I | cut -d\  -f1`
  echo "Test app is available at: http://${ip}:7080"
  echo -n "press enter to stop "; read x

  # cleanup
  kubectl delete service hello-minikube
  kubectl delete deployment hello-minikube
}

#-----------------------------------------------------------

configure_system
install_podman
install_crio
install_minikube
sudo dnf clean all     # cleanup

exit 0

