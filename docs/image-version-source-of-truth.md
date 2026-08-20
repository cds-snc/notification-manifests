# Image Version Source of Truth

## Goal

No Notify-owned image, in any environment, should ever be deployed by a mutable tag
(`:latest`, `:bootstrap`, or any tag a rebuild can silently overwrite). Every environment's
exact running version must be readable from one place without guessing, without querying ECR,
and without cloning another repo.

## Why this has been hard

Not because the idea is complicated — because today there are three disconnected mechanisms,
and none of them cover every image:

1. **Kubernetes app images** (admin/API/document-download/documentation/IPv4/Blazer) are
   tracked in this repo's `helmfile/overrides/{dev,staging,production}.env` and rendered by
   Helm. This is the only mechanism that already works end-to-end.
2. **Lambda images** are built by `notification-lambdas` into private, per-environment ECR
   accounts. Most of them were never wired into this repo's tracked files at all — three of
   them (heartbeat/system_status/ses_to_sqs_email_callbacks) were hardcoded literals inside a
   GitHub Actions `env:` block in `helmfile_production_apply.yaml`, invisible to the same
   dispatch/PR mechanism every other component uses. The rest (google-cidr,
   pinpoint_to_sqs_sms_callbacks, sns_to_sqs_sms_callbacks, ses_receiving_emails) are not
   deployed by this repo at all today.
3. **Terraform's bootstrap/recovery path** clones source and rebuilds images on the fly,
   tagging them literally `bootstrap` or `latest`. This is a break-glass mechanism that got
   conflated with normal deploys, so several Terraform locals still default to `bootstrap`/
   `latest` even outside of recovery.

Because these three mechanisms don't talk to each other, "what's actually running in
production right now" has never had one answer. Fixing that means giving every image family
the same treatment as mechanism (1) above, then deleting the special cases.

## The source of truth

`helmfile/overrides/{dev,staging,production}.env` in this repo is the canonical record. Every
tracked field is `<COMPONENT>_DOCKER_TAG`. Nothing that deploys to an environment should read
an image tag from anywhere else (not a workflow's `env:` block, not a Terraform default, not a
"pull `:latest`" step).

Producers publish an immutable tag (git SHA or equivalent) and either:

- dispatch an `update-docker-image` event to update `staging.env`/`dev.env` automatically
  (existing mechanism, `.github/workflows/update_image_tags_staging_and_dev.yaml`), or
- for `production.env`, land a normal reviewed PR bumping the tag (existing pattern, e.g. the
  `Updated manifests to notification-api:701ac57...` commits).

```json
{
  "event_type": "update-docker-image",
  "client_payload": { "component": "IPV4", "docker_tag": "<immutable-tag>" }
}
```

## Status of every deployed component

| Component | Tracked field | Producer | State |
| --- | --- | --- | --- |
| `notify-admin` | `ADMIN_DOCKER_TAG` | notification-admin | Tracked, immutable, dispatch-wired |
| `notify-api` | `API_DOCKER_TAG` | notification-api | Tracked, immutable, dispatch-wired |
| `notify-celery` / `notify-jobs` / `notify-database` | `API_DOCKER_TAG` (inherited) | notification-api | Tracked via API image |
| `notify-document-download` | `DOCUMENT_DOWNLOAD_DOCKER_TAG` | notification-document-download-api | Tracked, immutable, dispatch-wired |
| `notify-documentation` | `DOCUMENTATION_DOCKER_TAG` | notification-documentation | Tracked, immutable, dispatch-wired |
| `ipv4-geolocate` | `IPV4_DOCKER_TAG` | ipv4-geolocate-webservice | Tracked here, but producer still only publishes a date tag + `latest` and never dispatches |
| Blazer (web) | `BLAZER_DOCKER_TAG` | notification-lambdas | Tracked here, but value is still the literal `bootstrap` tag — producer doesn't publish a real release tag yet |
| Blazer (migrate init container) | fixed `ankane/blazer:v3.5.1` | upstream (ankane) | Already immutable, not a Notify image, no action needed |
| `heartbeat` / `system_status` / `ses_to_sqs_email_callbacks` Lambdas | `HEARTBEAT_DOCKER_TAG` / `SYSTEM_STATUS_DOCKER_TAG` / `SES_TO_SQS_EMAIL_CALLBACKS_DOCKER_TAG` | notification-lambdas | **Newly tracked in `production.env` this PR** (moved out of the hardcoded workflow `env:` block, same values, zero behavior change). Producer still also pushes `:latest`. |
| `google-cidr` Lambda | not tracked | notification-lambdas | Production is currently running `:latest` with no real tag recorded anywhere — needs the producer to resolve/publish a real tag before this repo can track it |
| `pinpoint_to_sqs_sms_callbacks` Lambda | not tracked | notification-lambdas | Built and pushed with a SHA tag today but never deployed from this repo |
| `sns_to_sqs_sms_callbacks` Lambda | not tracked | notification-terraform / legacy | Deployed via Terraform, not this repo; has stale/legacy image history |
| `ses_receiving_emails` Lambda | not tracked | notification-terraform / legacy | Same as above |
| Lambda log extension | not tracked | notification-terraform bootstrap path | Only exists as a `:latest` bootstrap build today |

## The plan, in order

1. **(Done, this PR)** Stop hiding tags in workflow files. Every Kubernetes/Lambda tag this
   repo actually deploys now lives in `helmfile/overrides/*.env`, nothing else.
2. **notification-lambdas**: stop pushing `:latest` for every image once each consumer below is
   confirmed to use the SHA tag instead; dispatch (or PR) each real tag to this repo the same
   way document-download/documentation already do.
3. **ipv4-geolocate-webservice**: publish a real immutable tag (source commit, not a date) and
   add the same dispatch call as the other producers. Remove the `:latest` push.
4. **Blazer producer** (notification-lambdas): publish a real release tag for the web image
   instead of `bootstrap`; once that exists, replace `BLAZER_DOCKER_TAG`'s value here.
5. **notification-terraform**: replace every `bootstrap`/`latest` fallback local with a value
   read from this repo's tracked tags (no live GitHub fetch during plan/apply). Keep the
   bootstrap/recovery path, but make it produce a unique `bootstrap-<env>-<run id>` tag, never
   the literal `bootstrap`.
6. **Remaining Lambdas** (google-cidr, pinpoint_to_sqs_sms_callbacks, sns_to_sqs_sms_callbacks,
   ses_receiving_emails, log extension): resolve and verify one real tag per environment per
   image (account, region, repository, digest, source commit), then add the tracked field here
   and wire the deploy step. Do this only after each value is independently confirmed — never
   copy a tag between environments or guess one.

Do not skip ahead to step 6 before steps 2-5 land; the whole point is one mechanism, not a
sixth special case.
