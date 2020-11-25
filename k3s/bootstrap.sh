#!/bin/bash

set -e -x
master="$1"
user="vagrant"

#sudo dnf upgrade -y
sudo dnf install -y \
    procps iproute iptables nftables \
    lsof psmisc curl ca-certificates sudo \
    vim-minimal openssh-clients gnupg2

export PATH=$PATH:/usr/local/bin
echo 'PATH=$PATH:/usr/local/bin; export PATH' | sudo tee -a .profile

#---------------------------------

set_creds(){
  mkdir -p ${HOME}/.ssh
  cp -v /vagrant/id_rsa* ${HOME}/.ssh
  cat ${HOME}/.ssh/id_rsa.pub >> ${HOME}/.ssh/authorized_keys
  chmod -R go-rwx ${HOME}/.ssh
  chown -R `id -un` ${HOME}/.ssh

  mkdir -p /home/${user}/.ssh
  cp -v /vagrant/id_rsa* /home/${user}/.ssh
  cat /home/${user}/.ssh/id_rsa.pub >> /home/${user}/.ssh/authorized_keys
  chmod -R go-rwx /home/${user}/.ssh
  chown -R ${user} /home/${user}/.ssh
}

k3sup_master(){
  test -e /usr/bin/kubectl || ln -s /usr/local/bin/kubectl /usr/bin/kubectl || :
  k3sup install --ip ${ip} --local     #--cluster-init  --write-kubeconfig-mode 0644
  KUBECONFIG=/home/${user}/kubeconfig; export KUBECONFIG
  cp -av /etc/systemd/system/k3s.service /etc/systemd/system/k3s.service.save
  extraopts="'--write-kubeconfig-mode' '0644'"
  sed -e "s/ server / server ${extraopts} /g" < /etc/systemd/system/k3s.service.save > /etc/systemd/system/k3s.service
  systemctl daemon-reload
  systemctl stop k3s.service || :
  sleep 3
  systemctl start k3s.service || :
  sleep 10
  systemctl status k3s.service || :
  kubectl get node -o wide || :
  cred_user=`kubectl config view -o jsonpath='{.users[].user.username}'`
  cred_pass=`kubectl config view -o jsonpath='{.users[].user.password}'`
  echo "K3s API is available at: https://${ip}:6443/"
  echo "Credentials: ${cred_user} // ${cred_pass}"
}

k3sup_worker(){
  test -e /usr/bin/kubectl || ln -s /usr/local/bin/kubectl /usr/bin/kubectl || :
  #k3sup join --ip ${ip} --server --server-ip "$master" || :
  k3sup join --ip ${ip} --server-ip "$master" || :
  sudo ls -al /etc/systemd/system/k3s* || :
  systemctl | grep -i k3 || :
  systemctl status k3s.service || systemctl status k3s-agent.service || :
}

user_env(){
  if test -f /home/${user}/kubeconfig; then
    mkdir -p /home/${user}/.kube
    cp -v /home/${user}/kubeconfig /home/${user}/.kube/config
    echo "KUBECONFIG=/home/${user}/kubeconfig; export KUBECONFIG" | sudo tee -a .profile
    chown -R ${user} /home/${user}/.kube
  fi
}

install_helm(){
  ver="v3.4.1"
  arch=`arch`
  case "$arch" in
    x86_64) arch=amd64;;
  esac
  cd /tmp
  curl -sL https://get.helm.sh/helm-${ver}-linux-${arch}.tar.gz -o helm.tar.gz
  tar -xvpSf helm.tar.gz
  mv linux-${arch}/helm /usr/local/bin/helm
}

install_dashboard(){
  name="dashboard"
  KUBECONFIG=/home/${user}/kubeconfig; export KUBECONFIG
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
  helm repo update
  helm install "my-$name" kubernetes-dashboard/kubernetes-dashboard

  sleep 20
  kubectl get pods -A
  sleep 20
  kubectl get pods -A
  pod_name=`kubectl get pods -n default -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=my-$name" -o jsonpath="{.items[0].metadata.name}"`
  sleep 10
  if kubectl wait --for=condition=ready pod/${pod_name}; then
    ( nohup kubectl -n default port-forward --address 0.0.0.0 ${pod_name} 8443:8443 1>forward.log 2>&1 ) &
  fi

  ip=`hostname -I | cut -d\  -f1`
  echo "Dashboard is available at: https://${ip}:8443/"
  # security token
  kubectl -n kube-system describe $(kubectl -n kube-system get secret -n kube-system -o name | grep namespace) | grep token:
}

#---------------------------------

set_creds
curl -sLS https://get.k3sup.dev | sh -x

echo -n 'Host IPs: '; hostname -I
ip=`hostname -I|cut -d\  -f1`
name="`hostname`"
case "$name" in
  *master*) role=master;;
  *worker*) role=worker;;
  *node*)   roe=worker;;
  *jump*)   role=jumphost;;
  *)        echo "unknown role for '$name'"; exit 99;;
esac

case "$role" in
  master) is_primary=0
          for ip in `hostname -I`; do
            if test "$master" = "$ip"; then
              is_primary=1
	      k3sup_master
	      install_helm
	      install_dashboard
	    fi
          done
          if test ${is_primary:-0} -eq 0
            then echo "invalid master defined '$master' != '$ip'" && exit 99
                 # install non primary master
          fi
          ;;
  worker) test "$master" = '' && echo "no master defined" && exit 99
	  k3sup_worker
          ;;
esac

user_env
sudo dnf clean all

exit 0

