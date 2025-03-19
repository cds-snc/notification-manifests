# notification-manifests

Kubernetes manifest files for [notification.canada.ca](https://notification.canada.ca).

## How does this repository work?

This repository uses Helm and Helmfile to manage the deployments of all notify components along with any kubernetes tools and deployments that are used across our GC Notify kubernetes cluster. The  [`helmfile/overrides`](helmfile/overrides) folder contains our environment specific configurations (ie. dev, staging, production, etc.).  Read up on helmfile overrides here:
[Helmfile Docs](https://helmfile.readthedocs.io/en/latest/)

## How are environment variables set?

Environment variables for this repository are managed by Helmfile.  

## How do I add a new environment variable?

As mentioned above, you will need to make changes to the `.env` file to include them in the `ConfigMap` object. In addition, you need to set up the `kustomization.yaml` file to include the new environment variable in the `ConfigMap`. This would look something like this if you wanted to add the variable `FOO` with the value `BAR`:

In a `.env` file add:

```
FOO=BAR
```

and then in `kustomization.yaml` add:

```yaml
- name: FOO
  objref:
    kind: ConfigMap
    name: application-config
    apiVersion: v1
  fieldref:
    fieldpath: data.FOO

```

under the `vars:` key.

You can now reference the variable in you other manifest files using `$(FOO)`.

You also need to add the new variable in `env.example` so that we can run CI without using any actual live variables.

The last thing you need to do is re-encrypt the `.env` file to make sure the variable gets saved. You can use the `make encrypt-staging` command to do this.

## How are image tag sets?

To adjust what images are used in the environments, you need to set them in the environment `kustomization.yaml` file:

```yaml
images:
  - name: admin
    newName: public.ecr.aws/cds-snc/notify-admin:latest
  - name: api
    newName: public.ecr.aws/cds-snc/notify-api:latest
  - name: document-download-api
    newName: public.ecr.aws/cds-snc/notify-document-download-api:latest
```

Will set the images in the base deployment to use `latest`.

In production, we use set image hashes directly, take a look at [`env/production/kustomization.yaml`](env/production/kustomization.yaml).

## Connecting to the database

1. First shell into the `jump-box` container inside the Kubernetes cluster (note the `-848d9c6787-p4r2v` suffix will be different):
```sh
kubectl exec -n notification-canada-ca -it jump-box-848d9c6787-p4r2v -- /bin/sh 
```

2. Use `socat` to forward all traffic from the `jump-box`'s port 5430 to the `DB_HOST_NAME` port 5432. `DB_HOST_NAME` should be something like `notification-canada-ca-staging-cluster.cluster-....ca-central-1.rds.amazonaws.com `
```sh
socat TCP-LISTEN:5430,fork TCP:DB_HOST_NAME:5432
```

3. Last, on your local machine, map the `jump-box` remote port 5430 to your local port 5430 (note the `-848d9c6787-p4r2v` suffix will be different):
```sh
kubectl port-forward -n notification-canada-ca jump-box-848d9c6787-p4r2v 5430:5430 
```

4. You can now connect to the database on your local port 5430 using the username and password. Please do not forget to terminate the `socat` connection with `Ctrl-C` once you are done.
