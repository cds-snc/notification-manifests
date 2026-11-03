# notification-manifests

Kubernetes manifest files for [notification.canada.ca](https://notification.canada.ca).

## How does this repository work?

This repository uses Helm and Helmfile to manage the deployments of all notify components along with any kubernetes tools and deployments that are used across our GC Notify kubernetes cluster. The  [`helmfile/overrides`](helmfile/overrides) folder contains our environment specific configurations (ie. dev, staging, production, etc.).  Read up on helmfile overrides here:
[Helmfile Docs](https://helmfile.readthedocs.io/en/latest/)

The notify API is deployed as a Kubernetes pod and is managed via Helm.

## Production image validation

Release PR planning and production deployment validate images before cluster
access, snapshots, database migrations, or application updates. The gate covers
the 13 Notify release images (14 image/region checks), not third-party platform
images. API, Celery, and database migrations share the API image.

The release bot supplies `release-images.json` with each selected full commit SHA,
its seven-character image tag, and source repository. Validation requires the
recorded tag to match both the selected SHA prefix and the tag in the production
configuration. Public ECR manifests are checked using Docker after authenticating
with ECR Public in `us-east-1`. Private ECR images are checked using the production
OIDC role and `ecr:DescribeImages` in each deployment region: `ca-central-1`,
`us-east-1`, and `us-west-2`. Existing diff and production apply roles have
`ReadOnlyAccess` plus ECR Public authentication permissions.

A missing image, revision/tag mismatch, invalid configuration, or inaccessible
registry blocks release. Slack and the workflow summary identify affected images
and distinguish missing tags from access/network errors. Setup failures also send
a Slack notification with a link to the failed run. No images are pulled, pushed,
retagged, or deployed by validation. Tag existence and SHA-prefix consistency do
not independently attest the contents of an image.

### Rollout and rollbacks

1. Merge the `notification-pr-bot` revision-record change first.
2. Run the existing release bot workflow to regenerate the release PR with its
	revision record, then merge the manifests gate change before releasing.
3. Confirm the production release PR's image validation passes before merging it.

Missing revision records fail closed, including manual production dispatches.
For manual releases or rollbacks, update/restore the full revision record and
production tags together. Validation uses the selected revision, not the current
component branch HEAD, so an older intended release remains valid if its images
still exist. Manifest-only releases can retain the existing record when tags do
not change. Regenerate older release PRs that predate this record.

### Local tests

```shell
cd .github/actions/validate-release-images
npm ci --ignore-scripts
npm test
```

Tests cover matching images, missing public/private tags, inconsistent SHA/config
values, registry errors, failure reporting, and production job dependencies. They
use fixtures and do not require AWS credentials. Live private-registry QA requires
an authenticated production AWS session; no production deployment is needed.

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

## Running Scheduled Scripts In Kubernetes

Use the dedicated `notify-jobs` chart with `helmfile/overrides/notify/jobs.yaml.gotmpl`.
This runs as a Helm-managed `CronJob` in staging and still consumes `api` plus `apiSecrets` values from `helmfile/overrides/notify/api.yaml.gotmpl`.

Safety guard:

- The `notify-jobs` Helmfile release is installed only for `--environment staging`.
- `dev` and `production` do not install this release.

Scheduled behavior:

1. Add script files under `helmfile/charts/notify-jobs/scripts/`.
2. Add one entry per script in `scheduledScriptCronJobs` in `helmfile/overrides/notify/jobs.yaml.gotmpl`.
3. Set `name`, `schedule`, `scriptType`, and `scriptPath` for each script.
4. Deploy with normal staging Helmfile apply.

Execution modes:

- `scriptType: shell` runs `/bin/sh <scriptPath>`
- `scriptType: python` runs `poetry run python <scriptPath>`

Built-in validation script behavior:

- Three dummy scheduled scripts are included:
	- `dummy-report-a.py`
	- `dummy-report-b.py`
	- `dummy-maintenance-c.sh`
- All scripts under `helmfile/charts/notify-jobs/scripts/` are mounted into the job pods at `/opt/notify-jobs-scripts`.

Long-run safety knobs:

- `cronJobDefaults.activeDeadlineSeconds`: hard timeout (default `43200` for 12 hours)
- `cronJobDefaults.backoffLimit`: retry count (`0` means do not retry)
- `cronJobDefaults.ttlSecondsAfterFinished`: cleanup time after completion

## Connecting to the database

1. Get the database connection URI from the AWS console under RDS

2. Connect to the appropriate VPN

3. Create a new connection to DBeaver with the appropriate connection string and credentials
