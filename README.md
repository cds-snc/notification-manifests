# notification-manifests
Kubernetes manifest files for notification.canada.ca

## How does this repository work?

This repository uses version 2.0.3 of [Kustomize](https://github.com/kubernetes-sigs/kustomize/tree/v2.0.3), which is baked into `kubectl` to apply different environment overlays (staging, production), on to an existing base configuration. As a result the `base` directory describes all the commonalities between all environments, while the `env/staging` and `env/production` directories contain the environment specific configurations. These include:

- Environment variables
- Target group bindings between the AWS network infrastructure and the kubernetes cluster
- Replica count patches (ex. How many pods of each type run in each environment)

## How are environment variables set?

`Kustomize` can dynamically inject environment variables when it compiles the configuration. To do this it reads out the environment variables and creates a `ConfigMap` object using an `.env` file that is in the same directory as the overlay that is being called from (ex. `/env/staging/.env`). As it is bad practice to save environment variables to a Git repository, the `.env` is ignored, and instead saved in an encrypted envelope using AWS KMS as `.env.enc.aws`. This means that before the overlay is applied, the file needs to be decrypted. There is a handy `make decrypt-staging` command that will do this for you if you have the correct AWS credentials configured. 

## How do I add a new environment variable?

As mentioned above, you will need to make changes to the `.env` file to include them in the `ConfigMap` object. In addition, you need to set up the `kustomization.yaml` file to include the new environment variable in the `ConfigMap`. This would look something like this if you wanted to add the variable `FOO` with the value `BAR`:

In `.env` add:

```
FOO=BAR
```

and then in `kustomization.yaml` add:

```
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

You also need to add the new vairable in `env.example` so that we can run CI without using any actual live variables.

The last thing you need to do is re-encrypt the `.env` file to make sure the variable gets saved. You can use the `make encrypt-staging` command to do this.

## How are image tag sets?

To adjust what images are used in the environments, you need to set them in the environment `kustomization.yaml` file:

```
images:
  - name: admin
    newName: public.ecr.aws/v6b8u5o6/cdssnc/notify/admin:latest
  - name: api
    newName: public.ecr.aws/v6b8u5o6/cdssnc/notify/api:latest
  - name: document-download-api
    newName: public.ecr.aws/v6b8u5o6/cdssnc/notify/document-download-api:latest
  - name: document-download-frontend
    newName: public.ecr.aws/v6b8u5o6/cdssnc/notify/document-download-frontend:latest
```

Will set the images in the base deployment to use `latest`.

## Connecting to the database:

1. First shell into the `jump-box` container inside the kubernetes cluster (note the `-848d9c6787-p4r2v` suffix will be different):
```
kubectl exec -n notification-canada-ca -it jump-box-848d9c6787-p4r2v -- /bin/sh 
```

2. Use `socat` to forward all traffic from the `jump-box`'s port 5430 to the `DB_HOST_NAME` port 5432. `DB_HOST_NAME` should be something like `notification-canada-ca-staging-cluster.cluster-....ca-central-1.rds.amazonaws.com `
```
socat TCP-LISTEN:5430,fork TCP:DB_HOST_NAME:5432
```

3. Last, on your local machine, map the `jump-box` remote port 5430 to your local port 5430 (note the `-848d9c6787-p4r2v` suffix will be different):
```
kubectl port-forward -n notification-canada-ca jump-box-848d9c6787-p4r2v 5430:5430 
```

4. You can now connect to the database on your local port 5430 using the username and password. Please do not forget to terminate the `socat` connection with `Ctrl-C` once you are done.