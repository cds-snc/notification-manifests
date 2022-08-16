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

## Checklist if releasing new version:
- [ ] I made sure that the changes are as expected in [Notify staging](https://staging.notification.cdssandbox.xyz/)
- [ ] I have checked if the docker images I am referencing exist
    - [ ] [api lambda](https://ca-central-1.console.aws.amazon.com/ecr/repositories/private/296255494825/notify/api-lambda?region=ca-central-1) (requires Notification-Production / AdministratorAccess login)
    - [ ] [api k8s](https://gallery.ecr.aws/v6b8u5o6/notify-api)
    - [ ] [admin](https://gallery.ecr.aws/v6b8u5o6/notify-admin)
    - [ ] [documentation](https://gallery.ecr.aws/v6b8u5o6/notify-documentation)
    - [ ] [document download API](https://gallery.ecr.aws/v6b8u5o6/notify-document-download-api)

## Checklist if making changes to Kubernetes:
- [ ] I know how to get kubectl credentials in case it catches on fire

## After merging this PR
- [ ] I have verified that the tests / deployment actions succeeded
- [ ] I have verified that any affected pods were restarted successfully
- [ ] I have verified that I can still log into [Notify production](https://notification.canada.ca)
- [ ] I have verified that the smoke tests still pass on production
- [ ] I have communicated the release in the #notify Slack channel.