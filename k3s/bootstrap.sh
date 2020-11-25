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

case "$role" in
  master) is_primary=0
          for ip in `hostname -I`; do
            if test "$master" = "$ip"; then
              is_primary=1
	      test -e /usr/bin/kubectl || ln -s /usr/local/bin/kubectl /usr/bin/kubectl || :
	      k3sup install --ip ${ip} --local     #--cluster-init
              echo "KUBECONFIG=/home/${user}/kubeconfig; export KUBECONFIG" | sudo tee -a .profile
              systemctl status k3s.service || :
	    fi
          done
          if test ${is_primary:-0} -eq 0
            then echo "invalid master defined '$master' != '$ip'" && exit 99
                 # install non primary master
          fi
          ;;
  worker) test "$master" = '' && echo "no master defined" && exit 99
	  test -e /usr/bin/kubectl || ln -s /usr/local/bin/kubectl /usr/bin/kubectl || :
          #k3sup join --ip ${ip} --server --server-ip "$master" || :
          k3sup join --ip ${ip} --server-ip "$master" || :
          echo "KUBECONFIG=/home/${user}/kubeconfig; export KUBECONFIG" | sudo tee -a .profile
          sudo ls -al /etc/systemd/system/k3s* || :
          systemctl | grep -i k3 || :
          systemctl status k3s.service || systemctl status k3s-agent.service || :
          journalctl -xe || :
          ;;
esac

mkdir -p /home/${user}/.kube
test -f /home/${user}/kubeconfig && cp -v /home/${user}/kubeconfig /home/${user}/.kube/config
chown -R ${user} /home/${user}/.kube

sudo dnf clean all

exit 0


#--------------

#         su - ${user} -c "kubectl get node -o wide"

#  level=warning msg="Unable to read /etc/rancher/k3s/k3s.yaml, please start server with --write-kubeconfig-mode to modify kube config permissions"
#  error: error loading config file "/etc/rancher/k3s/k3s.yaml": open /etc/rancher/k3s/k3s.yaml: permission denied

