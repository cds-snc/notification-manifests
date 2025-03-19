# notification-manifests

Kubernetes manifest files for [notification.canada.ca](https://notification.canada.ca).

## How does this repository work?

This repository uses Helm and Helmfile to manage the deployments of all notify components along with any kubernetes tools and deployments that are used across our GC Notify kubernetes cluster. The  [`helmfile/overrides`](helmfile/overrides) folder contains our environment specific configurations (ie. dev, staging, production, etc.).  Read up on helmfile overrides here:
[Helmfile Docs](https://helmfile.readthedocs.io/en/latest/)

Please note that our API runs as a Lambda Function -- which doesn't reside in Kubernetes.  While they are different platforms, we have set up helm to manage the configurations for both the lambda and Kubernetes dynamically.  Any configurations made to our helmfile configuration will be reflected in our Lambda API.

## How are environment variables added and set?

Environment variables for this repository are managed by Helmfile.  

### Non-secret configurations 
are set in the [`helmfile/overrides`](helmfile/overrides) folder where environment specific .env files contain the most basic environment specific configurations. Component specific helmfile overrides files are organized into folders within the [`helmfile/overrides`](helmfile/overrides) folder, and these manage the building of any necessary configurations for their corresponding deployments.
Adding an environment specific configuration looks likes this (NOTE - Helmfile will know which environment it is using based on its context):

'helmfile/overrides/yourenvironment.env'
```
YOUR_ADMIN_CONFIG_ENTRY: "yourenvironmentspecificvaluehere"
```

'helmfile/overrides/notify/admin.yaml.gotmpl'
```
YOUR_ADMIN_CONFIG_ENTRY_OVERRIDE:  "{{ .StateValues.YOUR_ADMIN_CONFIG_ENTRY }}"
```

### Secret configurations 
are set in [Terraform](https://github.com/cds-snc/notification-terraform) through a process involving 1password, terraform and AWS Secrets Manager.  If a secret has been added using the process outlined [here](https://github.com/cds-snc/notification-terraform/blob/main/docs/creatingSecrets.md), then you just have to declare or adjust a single line in the appropriate Helmfile overrides file in the secrets section. like so:
```
SECRET_NAME_FOR_ENV_PASSED_TO_CONTAINER: SECRET_NAME_READ_FROM_AWS_SECRETS_MANAGER 
```

If you've updated a secret in the 1password "single source of truth" -- that change will be reflected in AWS Secrets Manager during the next terraform release, and can then subsequently be consumed by our manifests workflows outlined here.

## Connecting to the database

1. Get the database connection URI from the AWS console under RDS

2. Connect to the appropriate VPN

3. Create a new connection to DBeaver with the appropriate connection string and credentials
