## What happens when your PR merges?

- Prefix the title of your PR:
  - `fix:` - tag `main` as a new patch release
  - `feat:` - tag `main` as a new minor release
  - `BREAKING CHANGE:` - tag `main` as a new major release
  - `[MANIFEST]` or `[AUTO-PR]` - tag `main` as a new patch release and deploy to production
  - `chore:` - use for changes to non-app code (ex: GitHub actions)
- Alternatively, change the [VERSION file](https://github.com/cds-snc/notification-manifests/blob/main/VERSION) - this will not create a new tag, but rather will release the tag in `VERSION` to production.

## What are you changing?

- [ ] Releasing a new version of Notify
- [ ] Changing kubernetes configuration

## Provide some background on the changes

> Give details ex. Security patching, content update, more API pods etc

## If you are releasing a new version of Notify, what components are you updating

- [ ] API
- [ ] Admin
- [ ] Documentation
- [ ] Document download API
- [ ] notification-lambdas

## Checklist if releasing new version

- [ ] I made sure that the changes are as expected in [Notify staging](https://staging.notification.cdssandbox.xyz/)
- [ ] I have checked if the docker images I am referencing exist
  - [ ] [api lambda](https://ca-central-1.console.aws.amazon.com/ecr/repositories/private/296255494825/notify/api-lambda?region=ca-central-1) (requires Notification-Production / AdministratorAccess login)
  - [ ] [api k8s](https://gallery.ecr.aws/v6b8u5o6/notify-api)
  - [ ] [admin](https://gallery.ecr.aws/v6b8u5o6/notify-admin)
  - [ ] [documentation](https://gallery.ecr.aws/v6b8u5o6/notify-documentation)
  - [ ] [document download API](https://gallery.ecr.aws/v6b8u5o6/notify-document-download-api)
  - [ ] notification-lambdas ([heartbeat](https://ca-central-1.console.aws.amazon.com/ecr/repositories/private/296255494825/notify/heartbeat?region=ca-central-1), [ses_to_sqs_email_callbacks](https://ca-central-1.console.aws.amazon.com/ecr/repositories/private/296255494825/notify/ses_to_sqs_email_callbacks?region=ca-central-1), [system-status](https://ca-central-1.console.aws.amazon.com/ecr/repositories/private/296255494825/notify/system_status?region=ca-central-1))

## Checklist if making changes to Kubernetes

- [ ] I know how to get kubectl credentials in case it catches on fire

## After merging this PR

- [ ] I have verified that the tests / deployment actions succeeded
- [ ] I have verified that any affected pods were restarted successfully
- [ ] I have verified that I can still log into [Notify production](https://notification.canada.ca)
- [ ] I have verified that the smoke tests still pass on production
- [ ] I have communicated the release in the #notify Slack channel.
