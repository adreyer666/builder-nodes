# builder-nodes

System setup

## Docker / Podman
Ensure you have upstream in the registry list:

```
# cat /etc/containers/registries.conf
[registries.search]
registries = ['docker.io', 'quay.io', 'registry.fedoraproject.org', 'registry.access.redhat.com']
```

