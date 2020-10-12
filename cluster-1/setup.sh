#!/bin/bash

test `id -u` -eq 0 && echo "DO NOT RUN AS ROOT" && exit 0

set -e

kcfg="/vagrant/${ID:-kcluster}-config.json"
test -f $kcfg || kcfg="./${ID:-kcluster}-config.json"
TOKEN=`jq -r .security.token <$kcfg`
HASH=`jq -r .security.hash <$kcfg`
PODNET=`jq -r .pod.network <$kcfg`
PODIP=`jq -r .pod.cluster_ip <$kcfg`
LENSVER=`jq -r .management.lens.version <$kcfg`
NETVER=`jq -r .management.flannel.version <$kcfg`
KUBEVER=`kubectl version --short 2>&- | cut -d: -f2 |tr -d ' '`


#----------------------------------------------------------------------------------------#

## Initialize the Control Plane
cplane_setup() {
  # Generate a bootstrap token to authenticate nodes joining the cluster
  test "$TOKEN" = 'null' && TOKEN=$(sudo kubeadm token generate)
  echo "Token: $TOKEN"

  sudo kubeadm init --token=${TOKEN} --kubernetes-version=${KUBEVER} --pod-network-cidr=${PODNET}

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  # Show the nodes in the Kubernetes cluster
  kubectl get nodes

  # Download the Flannel YAML data and apply it
  #kubectl apply -f podnetwork.yaml
  curl -sSL https://raw.githubusercontent.com/coreos/flannel/v${NETVER}/Documentation/kube-flannel.yml | kubectl apply -f -
}

node_join() {
  ## ## -- TODO -- ## ##
  if test "$HASH" = 'null';
    then  _hash="--discovery-token-unsafe-skip-ca-verification"
    else  _hash="--discovery-token-ca-cert-hash sha256:$HASH"
  fi
  # Join nodes to cluster
  kubeadm join ${KMASTER}:6443 --token ${TOKEN} ${_hash}
}

#----------------------------------------------------------------------------------------#

## Set up and test NFS provisioner (client side) ##

## Set up NFS provisioner ##
nfs_provisioner_setup(){
  cd /usr/local/src
  git clone https://github.com/kubernetes-incubator/external-storage.git
  cd external-storage/nfs-client/deploy

  # Create the RBAC permissions needed by the NFS provisioner
  kubectl create -f rbac.yaml

  echo "## TODO ##"
  echo "update deployment.yaml"
  cat <<eom
- First, set the three environment variables from the .spec.template.containers.env list:
  • Change the value for PROVISIONER_NAME to nfs-storage (optional; this just makes it a little more human-friendly).
  • Change the NFS_SERVER value to the IP address of your NFS server.
  • Change the NFS_PATH value to the path of your NFS export.
- Finally, under .spec.template.spec.volumes.nfs , change the server and path values to the same ones you set for the NFS_SERVER and NFS_PATH , respectively.
eom

  # Create the deployment
  kubectl create -f deployment.yaml

  # Check that the deployment created the provisioner pod correctly
  kubectl get po

  echo "## TODO ##"
  echo "update class.yaml"
  cat <<eom
The class.yaml file needs to be modified to set the provisioner value to nfs-storage or whatever you set for the PROVISIONER_NAME value in the deployment.yaml.
eom

  # Create the storage class
  kubectl create -f class.yaml

  # Verify the storage class was created
  kubectl get storageClass
}

## test nfs provisioner
nfs_provisioner_test(){
  # Look for existing persistent volumes
  kubectl get persistentvolumes

  # Look for existing persistent volume claims
  kubectl get persistentvolumeclaims

  # Create a test PVC
  kubectl create -f test-claim.yaml
  kubectl get persistentvolumeclaims

  cat > test-pod-1.yaml <<eom
kind: Pod
apiVersion: v1
metadata:
  name: test-pod
  spec:
    containers:
    - name: test-pod
      image: docker.io/aarch64/busybox:latest
      # image: gcr.io/google_containers/busybox:1.24
      command:
        - "/bin/sh"
      args:
        - "-c"
        - "touch /mnt/SUCCESS && exit 0 || exit 1"
      volumeMounts:
        - name: nfs-pvc
          mountPath: "/mnt"
    restartPolicy: "Never"
    volumes:
      - name: nfs-pvc
        persistentVolumeClaim:
          claimName: test-claim
eom
  # Create the test pod container
  kubectl create -f test-pod-1.yaml

  # Validate the container ran without problem
  kubectl get po

  # Cleanup the test-pod pod
  kubectl delete po test-pod

  # Cleanup the test-claim pvc
  kubectl delete pvc test-claim
}

#----------------------------------------------------------------------------------------#

deployment_test() {
  # Create a new namespace
  kubectl create namespace kube-verify
  # List the namespaces
  kubectl get namespaces

  # Create a new deployment
  cat <<EOF | kubectl create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-verify
  namespace: kube-verify
  labels:
    app: kube-verify
spec:
  replicas: 3
  selector:
    matchLabels:
      app: kube-verify
  template:
    metadata:
      labels:
        app: kube-verify
    spec:
      containers:
      - name: nginx
        image: quay.io/clcollins/kube-verify:01
        ports:
        - containerPort: 8080 $ kubectl get -n kube-verify service/kube-verify
EOF

  # Check the resources that were created by the deployment # Use curl to connect to the ClusterIP:
  kubectl get all -n kube-verify

  # Create a service for the deployment
  cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: kube-verify
  namespace: kube-verify
spec:
  selector:
    app: kube-verify
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
EOF

  # Examine the new service
  kubectl get -n kube-verify service/kube-verify

  # Use curl to connect to the ClusterIP:
  curl ${PODIP}
}


## LENS management ##
lens_setup() {
  # download and start
  cd /usr/local/src
  wget https://github.com/lensapp/lens/releases/download/v${LENSVER}/Lens-${LENSVER}.AppImage
  chmod +x Lens-${LENSVER}.AppImage
  sudo mv Lens-${LENSVER}.AppImage /usr/sbin/lens
  lens
}

exit 0

#----------------------------------------------------------------------------------------#


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

