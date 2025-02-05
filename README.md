# notification-manifests

Kubernetes manifest files for [notification.canada.ca](https://notification.canada.ca).

## How does this repository work?

This repository uses version 2.0.3 of [Kustomize](https://github.com/kubernetes-sigs/kustomize/tree/v2.0.3), which is baked into `kubectl` to apply different environment overlays (staging, production), on to an existing base configuration. As a result the `base` directory describes all the commonalities between all environments, while the [`env/staging`](env/staging) and [`env/production`](env/production) directories contain the environment specific configurations. These include:

- Environment variables
- Target group bindings between the AWS network infrastructure and the Kubernetes cluster
- Replica count patches (ex. How many pods of each type run in each environment)

## How are environment variables set?

### Environment Variables

Environment variables are set using a key/value pair in the values.yaml of the GC Notify helm charts, along with their overrides for each environment. [See the below section for adding a new environment variable.](##HowdoIaddanewenvironmentvariable?)

### Secrets

Secrets are set using Kubernetes secrets, which ensures that we do not ever spit sensitive information out on helmfile diffs or logs. [To add a secret please follow this guide.](https://github.com/cds-snc/notification-terraform/blob/main/docs/creatingSecrets.md)


## How do I add a new environment variable?

### READ THIS

If the value you are adding is a secret, DO NOT USE THIS METHOD. [Instead follow the instructions in the adding a secret document.](https://github.com/cds-snc/notification-terraform/blob/main/docs/creatingSecrets.md)

### Steps for everything but API

To add an environment variable for admin or celery, you will need to update up to 3 files. 

1. In the values.yaml file in helmfile/charts/notify-\<component\> add a new key value pair with the expected default value under the main component tag (ex. admin: or celeryCommon: etc)

```yaml
admin:
  NOTIFY_ENVIRONMENT: "default"
  AWS_REGION: "ca-central-1"
  ALLOW_HTML_SERVICE_IDS: "1,2,3,4"
  ........
  GC_ORGANISATIONS_BUCKET_NAME: "notification-canada-ca-default-gc-organisations"
  SENDING_DOMAIN: "notification.canada.ca"
  SOME_NEW_ENV_VAR: "someDefaultValue"
```

2. Add a corresponding value in the overrides file in helmfile/overrides/notify/\<component\>.yaml.gotmpl for the component. You have choices on how to configure this. 

If this is a straight up true/false feature flag, use 

```yaml
SOME_NEW_ENV_VAR: "{{ .StateValues.SOME_NEW_ENV_VAR }}"
```

If this is a string that changes based on environment name, you can leverage built in helmfile keywords:

```yaml
SOME_NEW_ENV_VAR: "notify-new-env-var-{{ .Environment.Name }}"
```

If this is a URL, you can leverage the BASE_DOMAIN environment variable that is set in getContext.sh

```yaml
SOME_NEW_ENV_VAR: "https://some-new-url.{{ requiredEnv "BASE_DOMAIN" }}"
```

3. If the value of the new environment variable can't be set dynamically with the environment name or required environment variables (i.e. a true/false feature flag), you must now modify each environment.env file in helmfile/overrides/\<environmnent\>.env (State Value Files) to include your new variable and its configuration for each environment.

staging.env

```yaml

ADMIN_DOCKER_TAG: "1d912b8"
API_DOCKER_TAG: "1270b81"
DOCUMENT_DOWNLOAD_DOCKER_TAG: "7f5dc9d"
......
GC_ORGANISATIONS_BUCKET_NAME: "notification-canada-ca-staging-gc-organisations"
SOME_NEW_ENV_VAR: "true"

```

production.env 

```yaml

ADMIN_DOCKER_TAG: "1d912b8"
API_DOCKER_TAG: "1270b81"
DOCUMENT_DOWNLOAD_DOCKER_TAG: "7f5dc9d"
......
GC_ORGANISATIONS_BUCKET_NAME: "notification-canada-ca-production-gc-organisations"
SOME_NEW_ENV_VAR: "false"

```

### Steps for API

Since the API is run on both kubernetes and AWS Lambda, you will need to modify the Terraform parameter store configuration as well. Follow the steps in the preceeding section and then [update the terraform file as necessary.](https://github.com/cds-snc/notification-terraform/blob/main/aws/lambda-api/secrets_manager.tf)

```terraform

resource "aws_ssm_parameter" "environment_variables" {
  count       = var.bootstrap ? 1 : 0
  name        = "ENVIRONMENT_VARIABLES"
  description = "Environment variables for the API Lambda function"
  type        = "SecureString"
  tier        = "Advanced"
  value       = <<EOF
ADMIN_CLIENT_SECRET=${var.manifest_admin_client_secret}
ALLOW_DEBUG_ROUTE=false
ALLOW_HTML_SERVICE_IDS=4de8b784-03a8-4ba8-a440-3bfea1b04fe6,ea608120-148a-4eba-a64c-4d9a8010e7b0
API_HOST_NAME=https://api.${var.base_domain}

........

CYPRESS_USER_PW_SECRET=${var.manifest_cypress_user_pw_secret}
CYPRESS_AUTH_CLIENT_SECRET=${var.manifest_cypress_auth_client_secret}
SOME_NEW_ENV_VAR: "some-value"
EOF
}


```

## How are image tag sets?

Image tags are automatically set via Notify PR Bot in the helmfile/overrides/\<environment\>.env file

```yaml

ADMIN_DOCKER_TAG: "3efe89b"
API_DOCKER_TAG: "1270b81"
DOCUMENT_DOWNLOAD_DOCKER_TAG: "7f5dc9d"
DOCUMENTATION_DOCKER_TAG: "025892e"

```

## Connecting to the database

1. Obtain the postgres credentials from the 1Password TERRAFORM_SECRETS_<ENVIRONMENT> secret: 
- app_db_user
- app_db_user_password
2. [Obtain the postgres URL from AWS](https://ca-central-1.console.aws.amazon.com/rds/home?region=ca-central-1#databases:)
3. Connect to the appropriate environment VPN
4. Connect to the database