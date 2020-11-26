#!/bin/bash

test `id -u` -eq 0 && echo "DO NOT RUN AS ROOT" && exit 0
test "$1" = '-D' && shift && set -x

set -e

share="/vagrant"
kcfg="${share}/kcluster-config.json"
scfg="${share}/status/sec.json"


#----------------------------------------------------------------------------------------#

get_role() {
  role=''
  mytype=`hostname | cut -d. -f1 | sed -e 's/[0-9]*$//g'`
  for ntype in `jq -r '.nodes | keys []' <$kcfg`; do
    nname=`sed -e 's/#{i}//g' <<<"$ntype"`
    test "${mytype}" = "${nname}" && role=`jq -r ".nodes[\"$ntype\"].role" <$kcfg`
  done
  echo "${role:-unknown}"
}

#----------------------------------------------------------------------------------------#

## Set up and test NFS provisioner (client side) ##

## Set up NFS provisioner ##
nfs_provisioner_setup(){
  mkdir -p ${share}/tmp
  cd ${share}/tmp
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
  test -f deployment.yaml.orig || cp -av deployment.yaml deployment.yaml.orig
  mypath="/datastore/projects/cmdb/adreyer666/builder-nodes/cluster-2/nfsroot"
  myip=`hostname -I | cut -d\  -f 1`
  sed -e 's!fuseim.pri/ifs!nfs-storage!g' -e "s/10.10.10.60/$myip/g" -e "s!/ifs/kubernetes!$mypath!g" \
    < deployment.yaml.orig > deployment.yaml

  # Create the deployment
  kubectl create -f deployment.yaml

  # Check that the deployment created the provisioner pod correctly
  kubectl get pods

  echo "## TODO ##"
  echo "update class.yaml"
  cat <<eom
The class.yaml file needs to be modified to set the provisioner value to nfs-storage or whatever you set for the PROVISIONER_NAME value in the deployment.yaml.
eom
  test -f class.yaml.orig || cp -av class.yaml class.yaml.orig
  sed -e 's!fuseim.pri/ifs!nfs-storage!g' \
    < class.yaml.orig > class.yaml

  # Create the storage class
  kubectl create -f class.yaml

  # Verify the storage class was created
  kubectl get storageClass

  # cleanup
  cd ${share}
  rm -r ${share}/tmp/external-storage
}

## test nfs provisioner
nfs_provisioner_test(){
  cd ${share}

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
  kubectl get pods

  # Cleanup the test-pod pod
  kubectl delete po test-pod

  # Cleanup the test-claim pvc
  kubectl delete pvc test-claim
}

#----------------------------------------------------------------------------------------#

deployment_test() {
  PODIP=`jq -r .pod.cluster_ip <$kcfg`
  mkdir -p ${share}/tmp
  cd ${share}/tmp

  # Create a new namespace
  kubectl create namespace kube-verify
  # List the namespaces
  kubectl get namespaces

  # Create a new deployment
  cat > deployment.yaml <<EOF
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
        - containerPort: 8080
EOF
  kubectl create -f deployment.yaml

  # Check the resources that were created by the deployment # Use curl to connect to the ClusterIP:
  kubectl get all -n kube-verify

  # Create a service for the deployment
  cat > service.yaml <<EOF
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
  kubectl create -f service.yaml

  # Examine the new service
  kubectl get -n kube-verify service/kube-verify

  # Use curl to connect to the ClusterIP:
  curl ${PODIP}
}


return
if test "`get_role`" = "master"; then
  nfs_provisioner_setup
  nfs_provisioner_test
  deployment_test
fi
exit 0

