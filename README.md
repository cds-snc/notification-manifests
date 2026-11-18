# notification-manifests

Kubernetes manifest files for [notification.canada.ca](https://notification.canada.ca).

## How does this repository work?

This repository uses Helm and Helmfile to manage the deployments of all notify components along with any kubernetes tools and deployments that are used across our GC Notify kubernetes cluster. The  [`helmfile/overrides`](helmfile/overrides) folder contains our environment specific configurations (ie. dev, staging, production, etc.).  Read up on helmfile overrides here:
[Helmfile Docs](https://helmfile.readthedocs.io/en/latest/)

The notify API is deployed as a Kubernetes pod and is managed via Helm.

## Secret scanning

The [TruffleHog workflow](.github/workflows/secret_scanning.yml) runs on every
pull request, regardless of which files change. Dev apply, staging and production
diff/apply, and individual staging rollouts must pass the same reusable scan
before any other jobs run, including image validation and pre-apply snapshots.
The scanner has read-only repository access and receives no AWS or 1Password
secrets.

Pull requests scan the PR's commits; pushes scan the pushed commits. Manual,
repository-dispatch, and local runs scan all available branches and tags.
Available refs can differ between a local clone and an Actions checkout.
Potential secrets and scan errors fail the workflow. Credential verification is
disabled so detected values are not sent to external services. Investigate
findings and rotate any exposed credentials before retrying.

The [baseline](.github/trufflehog-baseline.json) includes reviewed service-ID
false positives and a confirmed revoked historical exposure. Reviewed exceptions
must match an unverified finding's exact detector, commit, file, and SHA-256
digest of the detected value (`raw_sha256`), with a nonempty `reason`. An explicit
`"commit": "*"` permits that exact detector/value in that exact file across
commits only for recurring reviewed non-secret values, such as service IDs or
documentation placeholders. Active credentials
must never be baselined. A historical credential may be baselined only after
confirmed revocation, with an exact commit and a reason recording who confirmed
revocation and when; describe it as a revoked exposure, not a false positive.
Hashing is for matching, not a substitute for revocation. Do not copy exceptions
from other repositories without reviewing findings in this repository.

The [scan script](.github/scripts/scan-secrets.sh) prints finding locations and
baseline decisions, metrics, and counts without detected values, and adds counts
to the Actions job summary. Raw findings are stored in private temporary files
and deleted on exit. With Docker, Node.js, and `jq` installed:

```sh
bash .github/scripts/scan-secrets.sh
```

For private local investigation with an installed TruffleHog 3.99.7:

```sh
bash .github/scripts/scan-secrets.sh --native --output-dir "$HOME/trufflehog-manifests-review"
```

The output directory must not exist. It is created with private permissions and
retains `results.jsonl` (including detected values), `errors.log`, `report.json`,
`validation.log`, and `hashed.jsonl`, even on failure. Do not commit or share
these files. Both options are forbidden in GitHub Actions. Omit `--native` to use
the pinned Docker image instead.

Review retained findings interactively, with five historical source lines on
either side of each hit:

```sh
bash .github/scripts/review-secrets.sh "$HOME/trufflehog-manifests-review"
```

The local-only [reviewer](.github/scripts/review-secrets.sh) offers approval as a
non-secret or confirmed revoked exposure, skip (the default), or quit.
Every approval requires a reason; revoked exposures also require who confirmed
revocation and the confirmation date. Approvals save immediately to the baseline
with exact commits and value hashes, never wildcard commits. Existing baseline
matches are skipped, so restarting resumes unapproved findings. Source context
may expose credentials: do not record or share the terminal. Binary source and
verified findings cannot be approved through this reviewer.
After reviewing, rerun `bash .github/scripts/scan-secrets.sh --native` to apply
the updated baseline; the retained report is not modified.

The scanner image is pinned to the TruffleHog 3.99.7 multi-platform manifest
digest (Linux AMD64/ARM64), matching notification-terraform. When upgrading,
update the digest, version labels, and regression test together.
Run the synthetic regression tests without Docker or network access:

```sh
bash .github/scripts/scan-secrets.test.sh
bash .github/scripts/review-secrets.test.sh
```

## Image validation

Staging and production apply share a workflow that checks their configured image
tags exist in public/private ECR across all 14 image-region targets, using each
environment's AWS account and deployment role. Failure stops before snapshots or
deployment and notifies Slack with the environment, affected image, and reason.
Neither plan workflow runs this check. No separate HEAD comparison, release record,
or release-bot change is required. To test safely, temporarily configure a nonexistent
staging image tag instead of deleting a potentially shared image, then restore it.

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
