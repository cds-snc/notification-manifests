# Image Version Source of Truth

The environment files under `helmfile/overrides` are the committed image-version record for each deployment environment:

- `dev.env`
- `staging.env`
- `production.env`

Image-producing repositories must publish an immutable image tag and dispatch an `update-docker-image` event to `cds-snc/notification-manifests` with:

```json
{
  "event_type": "update-docker-image",
  "client_payload": {
    "component": "IPV4",
    "docker_tag": "<immutable-tag>"
  }
}
```

The manifests workflow writes the component's `*_DOCKER_TAG` to both `staging.env` and `dev.env`. Production values are changed through the normal production release process.

## Deployed Notify component matrix

The image record must cover every deployed Notify component, not only every Docker repository.

| Deployed component | Image record | Current producer | Relationship |
| --- | --- | --- | --- |
| `notify-admin` | `ADMIN_DOCKER_TAG` | `notification-admin` | Direct public ECR image |
| `notify-api` | `API_DOCKER_TAG` | `notification-api` | Direct public ECR image |
| `notify-celery` | `API_DOCKER_TAG` | `notification-api` | Shares the API image |
| `notify-database` | `API_DOCKER_TAG` | `notification-api` | Database migration image shares the API image |
| `notify-jobs` | `API_DOCKER_TAG` | `notification-api` | Shares the API image through `api.yaml.gotmpl` |
| `notify-document-download` | `DOCUMENT_DOWNLOAD_DOCKER_TAG` | `notification-document-download-api` | Direct public ECR image |
| `notify-documentation` | `DOCUMENTATION_DOCKER_TAG` | `notification-documentation` | Direct public ECR image |
| `ipv4-geolocate` | `IPV4_DOCKER_TAG` | `ipv4-geolocate-webservice` | Direct public ECR image |
| Blazer web deployment | `BLAZER_DOCKER_TAG` | `notification-lambdas` | Private ECR image also built by the Lambda repository |
| Blazer migration init container | fixed `ankane/blazer:v3.5.1` | Ankane upstream | Third-party pinned image; not a Notify release tag |
| `heartbeat` Lambda | Lambda tag record required | `notification-lambdas` | Private per-environment ECR |
| `system_status` Lambda | Lambda tag record required | `notification-lambdas` | Private per-environment ECR |
| `google-cidr` Lambda | Lambda tag record required | `notification-lambdas` | Private per-environment ECR |
| `pinpoint_to_sqs_sms_callbacks` Lambda | Lambda tag record required | `notification-lambdas` | Private per-environment ECR; also built in us-west-2 |
| `ses_to_sqs_email_callbacks` Lambda | Lambda tag record required | `notification-lambdas` | Private per-environment ECR |
| `sns_to_sqs_sms_callbacks` Lambda | Lambda tag record required | Terraform/bootstrap path and legacy image history | Private per-environment ECR; verify before migration |
| `ses_receiving_emails` Lambda | Lambda tag record required | Terraform/bootstrap path and legacy image history | Private per-environment ECR; verify before migration |
| Lambda log extension | Lambda tag record required | `notification-terraform` bootstrap path | Private ECR; currently has a `latest` fallback |

The current workflow directly updates these manifest fields:

- `ADMIN`
- `API` (therefore also Celery, jobs, and database)
- `DOCUMENT_DOWNLOAD`
- `DOCUMENTATION`
- `IPV4`
- `BLAZER`

Lambda fields are intentionally marked as required rather than populated with copied values until
the private ECR account, repository, region, digest, and source commit are verified per environment.

The following deployed images are infrastructure or third-party dependencies, not Notify release
images and should not be mixed into this contract: Alpine init containers, Signoz, Fluent Bit,
Velero, Kubernetes controllers, ingress, and the pinned Blazer migration image.

## Producer status verified on 2026-08-20

- `notification-api`, `notification-admin`, `notification-document-download-api`, and
  `notification-documentation` already publish short commit tags. Document download and
  documentation already dispatch their staging tag updates here; API and admin use the same
  existing dispatch pattern.
- `ipv4-geolocate-webservice` currently publishes `latest` and a date tag, updates Kubernetes
  directly, and does not dispatch to manifests. It needs a unique source-commit tag and a dispatch.
- `notification-lambdas` publishes short commit tags and `latest` to separate staging and
  production ECR accounts, updates staging Lambdas directly, and does not dispatch a complete
  Lambda version record here. Its production SBOM path also scans `latest`.
- `notification-terraform` still owns a recovery/bootstrap build path and has legacy `latest` or
  literal `bootstrap` fallbacks in normal image consumers. It must consume the committed record
  for ordinary deployments without fetching GitHub or rebuilding source during every plan.

## Producer migration requirements

- `notification-lambdas` must dispatch immutable tags for every Lambda image it publishes and stop pushing `latest` after consumers migrate.
- The Lambda inventory includes `heartbeat`, `system_status`, `google-cidr`,
  `pinpoint_to_sqs_sms_callbacks`, `ses_to_sqs_email_callbacks`,
  `sns_to_sqs_sms_callbacks`, and `ses_receiving_emails`; Terraform consumers must be migrated
  alongside the Lambda build matrix rather than only updating the three redeploy steps in this repo.
- Lambda image records must include the private ECR account, repository, region, and tag. They must not be resolved from public ECR.
- `notification-terraform` must consume committed image inputs for normal deployments and use a unique, explicitly supplied bootstrap tag only for recovery builds.
- `ipv4-geolocate-webservice` must publish a unique immutable tag, preferably the source commit, instead of only a date tag and `latest`.
- Blazer's producer must replace the mutable `bootstrap` publication with an immutable release tag before `BLAZER_DOCKER_TAG` can stop using that compatibility value.

Do not copy image tags between environments or retag an image until its digest, source commit, ECR account, and region have been verified.
