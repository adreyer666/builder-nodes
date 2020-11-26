#!/bin/bash

verbose=1 ; export verbose

DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND

sudo apt-get update -q
#sudo apt-get upgrade -q -y && sudo apt-get dist-upgrade -q -y

sudo apt-get install -q -y --no-install-recommends \
  procps iproute2 iptables nftables \
  lsof psmisc curl ca-certificates sudo \
  vim-tiny openssh-client gpg gpg-agent lrzip \
  jq runit nfs-common

share="/vagrant"
kcfg="${share}/kcluster-config.json"
scfg="${share}/status/sec.json"
test -f $kcfg || kcfg="./${ID:-kcluster}-config.json"

#-----------------------------------------------------------

err_exit() {
  echo "$@"
  exit 99
}

genhosts() {
  for ntype in `jq -r '.nodes | keys []' <$kcfg`; do
    c=`jq -r ".nodes[\"$ntype\"].count" <$kcfg`
    tmpl_ip=`jq -r ".nodes[\"$ntype\"].ip" <$kcfg`
    tmpl_name=`jq -r ".nodes[\"$ntype\"].hostname" <$kcfg`
    for i in `seq 1 ${c:-0}`; do
      node=`sed -e "s/#{i}/${i}/g" <<<"${ntype}"`
      ip=`sed -e "s/#{i}/${i}/g" <<<"${tmpl_ip}"`
      name=`sed -e "s/#{i}/${i}/g" <<<"${tmpl_name}"`
      echo "${ip} ${name} ${node}"
    done
  done | sudo tee -a /etc/hosts
  sudo sed -e 's/\(127.0.1.1.*\)$/# \1   ## genhosts/g' -i /etc/hosts
}

get_role() {
  verbose=1
  test ${verbose:-0} -gt 0 && echo "##########################" 1>&2
  role=''
  mytype=`hostname | cut -d. -f1 | sed -e 's/[0-9]*$//g'`
  for ntype in `jq -r '.nodes | keys []' <$kcfg`; do
    nname=`sed -e 's/#{i}//g' <<<"$ntype"`
    test ${verbose:-0} -gt 0 && echo "comparing $mytype - $nname" 1>&2
    test "${mytype}" = "${nname}" && role=`jq -r ".nodes[\"$ntype\"].role" <$kcfg`
  done
  test ${verbose:-0} -gt 0 && echo "role detected:  $mytype - $role" 1>&2
  echo "${role:-unknown}"
}

configure_system(){
  # Set SELinux in permissive mode (effectively disabling it)
  if "`which sestatus 2>&-`" != ''; then
    sestatus
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
  fi
  sudo swapoff -a

  # system
  sudo modprobe -v overlay
  sudo modprobe -v br_netfilter
  echo "kernel.unprivileged_userns_clone=1" | sudo tee /etc/sysctl.d/10-userns.conf
  echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/10-ip_forward.conf
  echo 'net.ipv4.ip_unprivileged_port_start = 0' | sudo tee /etc/sysctl.d/11-unpriviledged_ports.conf
  # Letting iptables see bridged traffic
  sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
  sudo sysctl --system
}

install_tools() {
  sudo apt-get install -q -y crudini git
  #sudo apt-get install apt-transport-https --yes
}

install_podman() {
  repo=`jq -r .sw.repos.libcontainer.url < ${kcfg}`
  # podman
  echo "deb ${repo} /" | sudo tee /etc/apt/sources.list.d/libcontainers.list
  curl -sL "${repo}/Release.key" | sudo apt-key add -

  sudo apt-get update -q
  sudo apt-get install -q -y --no-install-recommends \
    podman-rootless buildah runc umoci slirp4netns # tc

  sudo mkdir -p /etc/containers
  sudo touch /etc/containers/nodocker
}

install_crio() {
  repo=`jq -r .sw.repos.libcontainer.url < ${kcfg}`
  criorepo=`jq -r .sw.repos.crio.url < ${kcfg}`
  criover=`jq -r .sw.pkgs.crio.version < ${kcfg}`
  crioos=`jq -r .sw.pkgs.crio.os < ${kcfg}`
  # CRI-O
  echo "deb ${repo} /" | sudo tee /etc/apt/sources.list.d/libcontainers.list
  curl -sL "${repo}/Release.key" | sudo apt-key add -
  echo "deb ${criorepo}/${criover}/${crioos}/ /" | sudo tee /etc/apt/sources.list.d/libcontainers_cri-o_${criover}.list
  curl -sL "${criorepo}/${criover}/${crioos}/Release.key" | sudo apt-key add -

  sudo apt-get update -q
  sudo apt-get install -q -y cri-o cri-o-runc

  sudo ln -s /usr/libexec/podman/conmon /usr/bin		## fix hard baked PATH in crio binary..

  sudo systemctl daemon-reload
  sudo systemctl enable --now crio
  sudo systemctl restart crio
}

install_kubernetes() {
  kuberepo=`jq -r .sw.repos.kube.url < ${kcfg}`
  kubeos=`jq -r .sw.pkgs.kube.os < ${kcfg}` # xenial
  # kubernetes
  echo "deb ${kuberepo} kubernetes-${kubeos} main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

  sudo apt-get update -q
  sudo apt-get install -q -y kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl

  test -d /usr/lib/systemd/system/kubelet.service.d \
    && sudo tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOM
[Service]
CPUAccounting=true
MemoryAccounting=true
EOM
  test -f /etc/default/kubelet \
    || echo 'KUBELET_EXTRA_ARGS=--feature-gates="AllAlpha=false,RunAsGroup=true" --container-runtime=remote --cgroup-driver=systemd --container-runtime-endpoint="unix:///var/run/crio/crio.sock" --runtime-request-timeout=5m' | sudo tee /etc/default/kubelet

  test -d /var/lib/kubelet \
    || sudo mkdir -p /var/lib/kubelet
  if test -f /var/lib/kubelet/config.yaml;
    then  echo 'cgroupDriver: systemd' | sudo tee -a /var/lib/kubelet/config.yaml
    else  sudo tee /var/lib/kubelet/config.yaml <<EOM
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOM
  fi

  sudo systemctl daemon-reload
  sudo systemctl enable --now kubelet
  sudo systemctl restart kubelet
}

install_cleanup(){
  # cleanup
  sudo apt-get remove -y --purge \
    unattended-upgrades reportbug doc-debian debian-faq manpages man-db \
    debconf-i18n systemd-timesyncd gcc-9-base apt-listchanges \
    python2 python2.7 python2.7-minimal libpython2.7-minimal libpython2.7-stdlib
  #sudo apt-get remove --purge git git-man
  sudo apt-get autoremove -q -y --purge

  sudo apt-get install -f -y
  sudo apt-get clean && sudo rm -rf /tmp/* /var/lib/apt/lists/* /var/cache/apt/archives/partial
}


#-----------------------------------------------------------

## Initialize the Control Plane
cplane_setup_1() {
  kmaster=`jq -r .security.master <$kcfg`
  token=`jq -r .security.token <$kcfg`
  podnet=`jq -r .pod.network <$kcfg`
  podip=`jq -r .pod.cluster_ip <$kcfg`
  kubever=`kubectl version --short 2>&- | cut -d: -f2 |tr -d ' '`
  #
  test "${podnet:-null}" = 'null' && return
  test "${kubever:-null}" = 'null' && return

  # Generate a bootstrap token to authenticate nodes joining the cluster
  test "${token:-null}" = 'null' \
    && token=$(sudo kubeadm token generate)
  echo "Token: ${token}"

  #sudo kubeadm init --kubernetes-version=${kubever} --token=${token} --pod-network-cidr=${podnet}
  sudo kubeadm --v=5 init --token=${token} --pod-network-cidr=${podnet}

  thash=`sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`
  echo "{ \"hash\":\"sha256:${thash}\", \"token\":\"${token}\", \"master\":\"${kmaster}\" }" > ${scfg}
}

mgmt_run() {
  user=`jq -r .management.user <$kcfg`
  test "${user:-null}" = 'null' && err_exit ".management.user not defined"
  su - ${user} -c "$*"
}

cplane_setup_2() {
  user=`jq -r .management.user <$kcfg`
  test "${user:-null}" = 'null' && err_exit ".management.user not defined"
  id=`id -u ${user}`
  test "${id:-0}" = '0' && err_exit ".management.user (${user}) does not exist"
  home=`getent passwd ${user} | cut -d: -f 6`
  # admin environment
  mkdir -p ${share}/status/
  sudo cp -i /etc/kubernetes/admin.conf ${share}/status/kube.config
  mkdir -p ${home}/.kube
  cp -v ${share}/status/kube.config ${home}/.kube/config
  sudo chown ${id}:${id} ${home}/.kube/config

  # Show the nodes in the Kubernetes cluster
  mgmt_run kubectl get nodes

  # Download the Flannel YAML data and apply it
  #mgmt_run kubectl apply -f podnetwork.yaml
  curl -sSL https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml --output kube-flannel-updated.yml
  mgmt_run kubectl apply -f kube-flannel-updated.yml

  # wait for startup and save running config - if this fails: STOP!
  timeout=150
  sleeptime=10
  while test \! -f /run/flannel/subnet.env && test ${timeout:-0} -gt 0; do
    sleep $sleeptime
    timeout=`expr $timeout - $sleeptime`
  done
  cp -v /run/flannel/subnet.env ${share}/status/subnet.env || err_exit "timeout waiting for flannel network"
}

cplane_join() {
  user=`jq -r .management.user <$kcfg`
  test "${user:-null}" = 'null' && err_exit ".management.user not defined"
  id=`id -u ${user}`
  test "${id:-0}" = '0' && err_exit ".management.user (${user}) does not exist"
  home=`getent passwd ${user} | cut -d: -f 6`
  # admin environment
  mkdir -p ${home}/.kube
  cp -v ${share}/status/kube.config ${home}/.kube/config
  sudo chown ${id}:${id} ${home}/.kube/config

  # control plane node
  kmaster=`jq -r .master <$scfg`
  token=`jq -r .token <$scfg`
  thash=`jq -r .hash <$scfg`
  sudo kubeadm --v=5 join --control-plane ${kmaster}:6443 --token ${token} --discovery-token-ca-cert-hash ${thash}
  sudo mkdir -p /run/flannel && sudo cp -v ${share}/status/subnet.env /run/flannel/subnet.env || :
}

worker_join() {
  user=`jq -r .management.user <$kcfg`
  test "${user:-null}" = 'null' && err_exit ".management.user not defined"
  id=`id -u ${user}`
  test "${id:-0}" = '0' && err_exit ".management.user (${user}) does not exist"
  home=`getent passwd ${user} | cut -d: -f 6`
  # admin environment
  mkdir -p ${home}/.kube
  cp -v ${share}/status/kube.config ${home}/.kube/config
  sudo chown ${id}:${id} ${home}/.kube/config

  # worker node
  kmaster=`jq -r .master <$scfg`
  token=`jq -r .token <$scfg`
  thash=`jq -r .hash <$scfg`
  ## test "${thash:-null}" = 'null' && _hash="--discovery-token-unsafe-skip-ca-verification"
  sudo kubeadm --v=5 join ${kmaster}:6443 --token ${token} --discovery-token-ca-cert-hash ${thash}
  sudo mkdir -p /run/flannel && sudo cp -v ${share}/status/subnet.env /run/flannel/subnet.env || :
}


#-----------------------------------------------------------

setup_helm() {
  curl -sSL https://baltocdn.com/helm/signing.asc | sudo apt-key add -
  echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt-get update
  sudo apt-get install -q -y helm
}

setup_dashboard() {
  # dashver=`jq -r .management.dashboard.version <$kcfg`   # v2.0.4
  # dashaddress=`jq -r .management.dashboard.address <$kcfg`
  # dashaccess=`jq -r .management.dashboard.access <$kcfg`
  # kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/${dashver}/aio/deploy/recommended.yaml
  # nohup kubectl proxy --address=${dashaddress} --accept-hosts=${dashaccess} &

  mgmt_run helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
  mgmt_run helm repo update
  mgmt_run helm install my-release kubernetes-dashboard/kubernetes-dashboard

  sleep 30
  mgmt_run kubectl get pods -n default
  pod_name=`mgmt_run kubectl get pods -n default -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=my-release" -o jsonpath="{.items[0].metadata.name}"`
  sleep 10
  if mgmt_run kubectl wait --for=condition=ready pod/${pod_name}; then
    ( mgmt_run nohup kubectl -n default port-forward --address 0.0.0.0 ${pod_name} 8443:8443 1>forward.log 2>&1 )&
  fi

  ip=`hostname -I | cut -d\  -f1`
  echo "Dashboard is available at: https://${ip}:8443/"
  # security token
  kubectl -n kube-system describe $(kubectl -n kube-system get secret -n kube-system -o name | grep namespace) | grep token:
}

## LENS management ##
setup_lens() {
  lensver=`jq -r .management.lens.version <$kcfg`

  # pre-requisites
  sudo apt-get install -q -y --no-install-recommends \
    fuse \
    libx11-6 libx11-xcb1 libxcb-dri3-0 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxi6 libnss3 libatk1.0-0 libatk-bridge2.0-0 libgdk-pixbuf2.0-0 libgtk-3-0 libdrm2 libgbm1 libasound2

  # download and start
  cd /usr/local/src
  curl -sSL https://github.com/lensapp/lens/releases/download/v${lensver}/Lens-${lensver}.AppImage --output Lens.AppImage
  chmod +x Lens.AppImage
  sudo mv Lens.AppImage /usr/sbin/lens
  nohup /usr/sbin/lens &
}


#-----------------------------------------------------------

test \! -f $kcfg && echo "missing configuration file $kcfg" && exit 1

role=`get_role`

genhosts
configure_system
case "${role:-unknown}" in
  'worker'|'master')
    install_tools
    install_podman
    install_crio
    install_kubernetes
    ;;
esac
install_cleanup

case "${role:-unknown}" in
  'master'|'control plane node')
    # ---- staging area ---- #
    sudo crudini --set /etc/containers/registries.conf registries.insecure registries "['registry:5000','registry.office.adreyer.com:5000']"
    #sudo crudini --set /etc/containerd/config.toml plugins.cri systemd_cgroup "true"

    # user
    su - vagrant -c "git config --global pull.ff only"
    mkdir -p /usr/local/src
    mkdir -p /usr/local/bin
    chown -R vagrant: /usr/local/src

    # pull kubeadm images
    sudo kubeadm config images pull

    if test -f $scfg;
      then
        ## control plane node (not primary/master)
        cplane_join
      else
        ## control plane node (primary/master)
        cplane_setup_1
        cplane_setup_2

	setup_helm
	setup_dashboard
        install_cleanup
    fi
    ;;
  'worker')
    sudo crudini --set /etc/containers/registries.conf registries.insecure registries "['registry:5000','registry.office.adreyer.com:5000']"
    test -f $scfg && worker_join
    ;;
  'jumphost')
    ;;
  'unknown')
    echo "unknown role - `hostname`"
    exit 1
    ;;
  *)
    echo "unknown role"
    exit 1
    ;;
esac

exit 0

#----------------------------------------------------------------------------------------#

#set cfg server address and access token enviroment variables
export cfgURL="http://bootstrap@desktop.lan:8200"
export token="nvfkivgewrjgtoirewnh"
# CA
curl -skL --oauth2-bearer "${token}" ${cfgURL}/pki_int/issue/leaf-cert/kubernetes > ca.json
cat ca.json | jq -r .data.certificate > ca-cert.pem
cat ca.json | jq -r .data.issuing_ca > ca.pem
cat ca.json | jq -r .data.private_key > ca-key.pem
rm ca.json
# Admin
curl -skL --oauth2-bearer "${token}" ${cfgURL}/pki_int/issue/leaf-cert/admin > admin.json
cat admin.json | jq -r .data.certificate > admin.pem
cat admin.json | jq -r .data.private_key > admin-key.pem
rm admin.json
# Nodes
NODES=4
for (( S=0; S<=$NODES; S++ )); do
  curl -skL --oauth2-bearer "${token}" ${cfgURL}/pki_int/issue/leaf-cert/node$S > node$S.json
  cat node$S.json | jq -r .data.certificate > node$S.pem
  cat node$S.json | jq -r .data.private_key > node$S-key.pem
  rm node$S.json
done

