# Container Runtime setup


## CRI-O
```
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo \
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_7/devel:kubic:libcontainers:stable.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.repo \
    https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.18/CentOS_7/devel:kubic:libcontainers:stable:cri-o:1.18.repo
dnf install -y cri-o
ln -s /bin/conmon /usr/libexec/crio
systemctl daemon-reload
systemctl start crio
```

### Result

```
W0715 14:37:41.837678   30055 configset.go:202] WARNING: kubeadm cannot validate component configs for API groups [kubelet.config.k8s.io kubeproxy.config.k8s.io]
failed to pull image "k8s.gcr.io/kube-apiserver:v1.18.5": output: time="2020-07-15T14:38:31Z" level=fatal msg="failed to connect: failed to connect: context deadline exceeded", error: exit status 1
```


## Podman
```
```

