# Summary | Résumé

_TODO: 1-3 sentence description of the changed you're proposing._

## Related Issues | Cartes liées

* https://app.zenhub.com/workspaces/notify-planning-614b3ad91bc2030015ed22f5/issues/gh/cds-snc/notification-planning/1
* https://app.zenhub.com/workspaces/notify-planning-core-6411dfb7c95fb80014e0cab0/issues/gh/cds-snc/notification-planning-core/1

## Release Instructions | Instructions pour le déploiement

None.

## Reviewer checklist | Liste de vérification du réviseur

* [ ] This PR does not break existing functionality.
* [ ] This PR does not violate GCNotify's privacy policies.
* [ ] This PR does not raise new security concerns. Refer to our GC Notify Risk Register document on our Google drive.
* [ ] This PR does not significantly alter performance.
* [ ] Additional required documentation resulting of these changes is covered (such as the README, setup instructions, a related ADR or the technical documentation).

> ⚠ If boxes cannot be checked off before merging the PR, they should be moved to the "Release Instructions" section with appropriate steps required to verify before release. For example, changes to celery code may require tests on staging to verify that performance has not been affected.

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

* [ ] I have verified that the tests / deployment actions succeeded
* [ ] I have verified that the smoke tests still pass on production
* [ ] I have communicated the release in the #notify Slack channel

## What happens when your PR merges?

* Prefix the title of your PR:
  * `fix:` - tag `main` as a new patch release
  * `feat:` - tag `main` as a new minor release
  * `BREAKING CHANGE:` - tag `main` as a new major release
  * `[MANIFEST]` - tag `main` as a new patch release and deploy to production
  * `chore:` - use for changes to non-app code (ex: GitHub actions)
* Alternatively, change the [VERSION file](https://github.com/cds-snc/notification-manifests/blob/main/VERSION) - this will not create a new tag, but rather will release the tag in `VERSION` to production.
