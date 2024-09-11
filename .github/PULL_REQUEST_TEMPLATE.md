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

## Checklist if releasing new version

- [ ] I made sure that the changes are as expected in [Notify staging](https://staging.notification.cdssandbox.xyz/)
- [ ] I have checked if the docker images I am referencing exist
  - [ ] [api lambda](https://ca-central-1.console.aws.amazon.com/ecr/repositories/private/296255494825/notify/api-lambda?region=ca-central-1) (requires Notification-Production / AdministratorAccess login)
  - [ ] [api k8s](https://gallery.ecr.aws/v6b8u5o6/notify-api)
  - [ ] [admin](https://gallery.ecr.aws/v6b8u5o6/notify-admin)
  - [ ] [documentation](https://gallery.ecr.aws/v6b8u5o6/notify-documentation)
  - [ ] [document download API](https://gallery.ecr.aws/v6b8u5o6/notify-document-download-api)

## Checklist if making changes to Kubernetes

- [ ] I know how to get kubectl credentials in case it catches on fire

## Before merging this PR

Read code suggestions left by the
[cds-ai-codereviewer](https://github.com/cds-snc/cds-ai-codereviewer/) bot. Address
valid suggestions and shortly write down reasons to not address others. To help
with the classification of the comments, please use these reactions on each of the
comments made by the AI review:

| Classification      | Reaction | Emoticon |
|---------------------|----------|----------|
| Useful              | +1       | 👍        |
| Noisy               | eyes     | 👀        |
| Hallucination       | confused | 😕        |
| Wrong but teachable | rocket   | 🚀        |
| Wrong and incorrect | -1       | 👎        |

The classifications will be extracted and summarized into an analysis of how helpful
or not the AI code review really is.

## After merging this PR

- [ ] I have verified that the tests / deployment actions succeeded
- [ ] I have verified that any affected pods were restarted successfully
- [ ] I have verified that I can still log into [Notify production](https://notification.canada.ca)
- [ ] I have verified that the smoke tests still pass on production
- [ ] I have communicated the release in the #notify Slack channel.
