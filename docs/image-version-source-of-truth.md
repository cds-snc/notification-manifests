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

Currently tracked by this workflow:

- `ADMIN`
- `API`
- `DOCUMENT_DOWNLOAD`
- `DOCUMENTATION`
- `IPV4`
- `BLAZER`

## Producer migration requirements

- `notification-lambdas` must dispatch immutable tags for every Lambda image it publishes and stop pushing `latest` after consumers migrate.
- Lambda image records must include the private ECR account, repository, region, and tag. They must not be resolved from public ECR.
- `notification-terraform` must consume committed image inputs for normal deployments and use a unique, explicitly supplied bootstrap tag only for recovery builds.
- `ipv4-geolocate-webservice` must publish a unique immutable tag, preferably the source commit, instead of only a date tag and `latest`.
- Blazer's producer must replace the mutable `bootstrap` publication with an immutable release tag before `BLAZER_DOCKER_TAG` can stop using that compatibility value.

Do not copy image tags between environments or retag an image until its digest, source commit, ECR account, and region have been verified.
