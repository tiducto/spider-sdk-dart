# Releasing `spider_sdk` to pub.dev

Publishing is automated with **pub.dev automated publishing over GitHub Actions OIDC**
(`.github/workflows/publish.yml`) — no long-lived pub.dev token or secret is stored.
pub.dev exchanges a short-lived GitHub OIDC token for a one-shot publish credential, and
only trusts runs triggered by a git **tag** matching the pattern `{{version}}`.

## One-time setup (maintainer)

Automated publishing cannot create a brand-new package, and a first publish needs a human,
so do these once before the pipeline can take over.

1. **Claim the name with a manual first publish.** From a clean checkout at the release
   commit (with the Dart SDK installed):
   ```bash
   dart pub publish --dry-run   # expect: no warnings on a clean git state
   dart pub publish             # authenticates in the browser; uploads spider_sdk 0.1.0
   ```
   This registers `spider_sdk` on pub.dev and makes you its uploader. (Version `0.1.0` is
   already set in `pubspec.yaml` — do not bump it for this step.)

2. **(Optional) Verified publisher for `tiducto.eu`.** On pub.dev → the package → **Admin**
   tab → *Publisher*, create/attach a verified publisher for the `tiducto.eu` domain
   (proves ownership via DNS/site verification and shows the verified badge on the page).

3. **Enable Automated publishing from GitHub Actions.** pub.dev → the package → **Admin**
   tab → *Automated publishing* → **Enable publishing from GitHub Actions**:
   - Repository: `tiducto/spider-sdk-dart`
   - Tag pattern: `{{version}}`  (this matches the `[0-9]+.[0-9]+.[0-9]+` trigger in the
     workflow, e.g. tag `0.1.0` publishes version `0.1.0`)
   - *(Optional, recommended)* tick **Require a GitHub Actions environment** and set it to
     `pub.dev`. The workflow already runs its publish job in an `environment: pub.dev`, so
     this matches out of the box; you can then add branch/reviewer protection to that
     environment under GitHub → Settings → Environments.

## Cutting a release (every version after the first)

1. Update `version:` in `pubspec.yaml` and add a matching `## <version> - <date>` section
   at the top of `CHANGELOG.md`.
2. Commit to `main` and push.
3. Tag the release commit with the exact pubspec version and push the tag:
   ```bash
   git tag 0.2.0        # must equal `version:` in pubspec.yaml
   git push origin 0.2.0
   ```
4. The **Publish to pub.dev** workflow runs on the tag: it first gates on
   `dart analyze --fatal-infos` + `dart test`, then publishes over OIDC. Watch it under the
   repo's **Actions** tab; the new version appears on pub.dev when it turns green.

Notes:
- The tag drives the publish. Pushing to `main` alone never publishes.
- The tag version and `pubspec.yaml` `version:` must be identical, or pub.dev rejects the run.
- Re-tagging an already-published version fails (pub.dev versions are immutable) — bump first.
