# Automated release with GitHub Actions

Pushing a tag `vX.Y.Z` builds the signed and notarized DMG on GitHub, and publishes the GitHub release with the DMG and the Sparkle appcast. Nothing has to run on the maintainer's Mac.

The manual procedure ([releasing.md](releasing.md)) still works and uses the same `scripts/release.sh`.

## What the pipeline does

The workflow is [`.github/workflows/release.yml`](../.github/workflows/release.yml). It runs on a `macos-26` runner (Xcode 26, Swift 6.2 or later; free for a public repository). The release needs it: an older runner builds an app without Liquid Glass and without translations (see [ADR 0008](adr/0008-release-built-on-github-actions-xcode-26.md)).

| # | Step | Fails when |
| --- | --- | --- |
| 1 | Clone the **full** history | (the build number is the commit count: a shallow clone would break updates) |
| 2 | Check that the tag matches the `VERSION` file | tag `v1.1.0` but `VERSION` says `1.0.9` |
| 3 | Read the `CHANGELOG.md` section of the version | the section is missing or empty |
| 4 | `swift test` | a test fails |
| 5 | Import the Developer ID certificate into a temporary keychain | a certificate secret is wrong |
| 6 | `scripts/release.sh --notarize`: build, sign, DMG, notarize, staple, appcast | signing or notarization is refused |
| 7 | Upload the DMG and the appcast as a workflow artifact | |
| 8 | Create the GitHub release `vX.Y.Z` with the DMG, the appcast and the changelog notes | the release already exists |

Step 8 only runs for a tag. The DMG and the appcast go up in the same release, so the feed never points to a missing file.

**How users get the appcast.** The app reads `https://soaro.app/appcast.xml`. The website redirects that address (`site/_redirects`) to `https://github.com/sebmafate/soaro/releases/latest/download/appcast.xml`, the appcast of the latest release. `main` is protected (pull request and signed commits required), so the pipeline never pushes to it.

## One-time setup

Do this once, from the Mac that already has the certificate and the Sparkle key.

### 1. Export the Developer ID certificate

1. Open **Keychain Access**, category **My Certificates**.
2. Right-click **Developer ID Application: Sebastien Ferrand (K8H46QQHGX)**, then **Export**. Choose the `.p12` format and set a strong password.
3. Make sure the certificate is exported **with its private key** (the entry has a small arrow you can unfold).

### 2. Create an app-specific password for notarization

On <https://account.apple.com> go to **Sign-In and Security**, **App-Specific Passwords**, and create one named `soaro-ci`. You can revoke it at any time.

### 3. Export the Sparkle private key

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/soaro-sparkle-key
```

The file holds one line. It is the same key as in [updates.md](updates.md#the-eddsa-keys): if you already made the backup, you can use that file.

### 4. Store the six secrets in the `release` environment

Since 2026-11-18 the secrets live in the GitHub **Environment** `release` (Settings, Environments), not in the repository secrets: the job declares `environment: release`, so every run waits for the required reviewer and only `main` and the tags `v*` may use them. Use the `gh` CLI with `--env release`, which reads the value from a file or from the terminal so nothing is written to your shell history.

```bash
cd ~/.t3/projects/mycleaner

base64 -i ~/Desktop/soaro-developer-id.p12 | gh secret set MACOS_CERTIFICATE --env release
gh secret set MACOS_CERTIFICATE_PASSWORD --env release   # paste the .p12 password
gh secret set APPLE_ID --env release                     # your Apple ID e-mail
gh secret set APPLE_APP_PASSWORD --env release           # the app-specific password from step 2
gh secret set APPLE_TEAM_ID --env release --body K8H46QQHGX
gh secret set SPARKLE_PRIVATE_KEY --env release < /tmp/soaro-sparkle-key
```

Check with `gh secret list --env release`: the six names of the table below must appear, and `gh secret list` (the repository secrets) must be empty, otherwise any workflow could still read them without the protection.

| Secret | Content |
| --- | --- |
| `MACOS_CERTIFICATE` | The `.p12` file, base64 encoded |
| `MACOS_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12` |
| `APPLE_ID` | Apple ID e-mail used for the notary service |
| `APPLE_APP_PASSWORD` | App-specific password (not the Apple ID password) |
| `APPLE_TEAM_ID` | `K8H46QQHGX` |
| `SPARKLE_PRIVATE_KEY` | Content of the file made by `generate_keys -x` |

### 5. Delete the temporary files

```bash
rm -P ~/Desktop/soaro-developer-id.p12 /tmp/soaro-sparkle-key
```

Keep the backup of the Sparkle key in your password manager (see [updates.md](updates.md#the-eddsa-keys)).

### 6. Hardening

**Done in the workflow (2026-11-18, after the first security review):**

- **Only reviewed code gets the secrets.** The first step after the checkout, `Only build reviewed code`, fails the run before any secret is read when the tagged commit is not an ancestor of `origin/main`, and refuses a manual run that is not started from `main`.
- **The write token is not left in the checkout.** `actions/checkout` runs with `persist-credentials: false`; the workflow is read-only by default and only this job has `contents: write`, which the last step (`gh release create`, with `GH_TOKEN`) uses. `ci.yml` is read-only too.
- Not done on purpose: splitting the build and the publish into two jobs (the publish job could not be tested without publishing) and pinning the GitHub actions by commit (`@v4` is kept).

**GitHub settings, by the owner (not code):** the two steps below. The Environment is done; the tag ruleset is still to do. Without it a person or a stolen token with write access can still push a tag from `main` (the run would then wait for your approval in the Environment, which is the last line of defence).

1. **A protected Environment: done on 2026-11-18.** The Environment `release` has the owner as required reviewer (self-review allowed, there is a single maintainer), allows only the branch `main` and the tags `v*`, holds the six secrets, and the repository secrets were deleted; the job declares `environment: release`. Every release, and every trial run, waits for your click in the Actions tab. Fork pull requests never receive the secrets either way.
2. **A tag ruleset.** In Settings, Rules, Rulesets, add a **tag** ruleset for `v*`: restrict creations, updates and deletions to the repository admin (bypass list), and require signed commits. Then create release tags with `git tag -s vX.Y.Z` (today the tags are lightweight and unsigned). This is a repository setting that only the owner can change; nothing in the code applies it.

## Trial run (nothing is published)

Do this before the first real release.

1. Push the workflow to GitHub (merge it into `main`).
2. In the **Actions** tab choose **Release**, **Run workflow**, branch `main`.
3. Keep **notarize** on to test the Apple credentials too (a few minutes). The run first waits for your approval (Review deployments, Approve) because the job uses the `release` environment.
4. When it is green, download the workflow artifact `soaro-<version>` and test the DMG on a Mac (see "Check the result" below).

A manual run never creates a release and never touches the website. A failure in step 5 or 6 almost always means a wrong secret.

## Publishing a version

1. Check that `swift test` passes locally.
2. Edit `VERSION` (for example `1.1.0`).
3. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [1.1.0] - 2026-MM-DD` and add a fresh empty `## [Unreleased]` above it. The text of that section becomes the release notes **and** what Sparkle shows to users.
4. Commit on a branch and merge it into `main` through a pull request (the ruleset requires it).
   ```bash
   git switch -c release/1.1.0
   git commit -am "Version 1.1.0"
   git push github release/1.1.0
   gh pr create --fill && gh pr merge --squash --admin
   git switch main && git pull github main
   ```
5. Tag and push the tag. This starts the pipeline.
   ```bash
   git tag v1.1.0
   git push github v1.1.0
   ```
6. Follow the run:
   ```bash
   gh run watch
   ```
   It takes about 10 to 20 minutes, most of it notarization.

## Check the result

1. The release `v1.1.0` exists on GitHub with `Soaro-1.1.0.dmg`: `gh release view v1.1.0`.
2. Download the DMG from GitHub (a download keeps the quarantine flag, like a user's). Then:
   ```bash
   spctl -a -t open --context context:primary-signature -vv Soaro-1.1.0.dmg
   xcrun stapler validate Soaro-1.1.0.dmg
   ```
   You must see `accepted` and `source=Notarized Developer ID`.
3. Open the DMG, drag the app to Applications, launch it. No Gatekeeper warning must appear.
4. `curl -sL https://soaro.app/appcast.xml` lists the new version (the redirect needs the website with `_redirects` deployed once).
5. From the **previous** version, use "Check for updates..." and install the update.

## If something goes wrong

| Symptom | Cause and fix |
| --- | --- |
| `Only build reviewed code` fails | The tag points to a commit that is not on `main` (merge the pull request first, then tag the merge commit), or a manual run was started from another branch (use `main`) |
| Step 2: tag does not match `VERSION` | Fix `VERSION`, then move the tag: `git tag -d v1.1.0 && git push github :refs/tags/v1.1.0`, commit, tag again |
| Step 3: no section `[1.1.0]` | Rename `Unreleased` in `CHANGELOG.md` (the heading must contain `[1.1.0]`) |
| Step 5: no identity found | `MACOS_CERTIFICATE` was exported without its private key, or is not base64 of the `.p12`. Export it again |
| `errSecInternalComponent` while signing | Wrong `MACOS_CERTIFICATE_PASSWORD`, or the certificate is not a *Developer ID Application* one |
| Step 6: notarization "Invalid" | Read the log in the run, or `xcrun notarytool log <id> --apple-id ... --team-id ... --password ...`. See [releasing.md](releasing.md#if-something-goes-wrong) |
| Step 6: notary "HTTP 401" | `APPLE_ID` or `APPLE_APP_PASSWORD` is wrong or revoked. The Apple Developer agreement may also need to be accepted again |
| Step 6: Sparkle key error | `SPARKLE_PRIVATE_KEY` is empty or has extra text. Set it again from the file |
| The run was cancelled after step 8 | Do not rerun the tag: `gh release create` would fail. Delete the release (`gh release delete v1.1.0`), then rerun the failed workflow |

To pull a bad release, see [releasing.md](releasing.md#if-something-goes-wrong).

## Good to know

- **The appcast keeps the latest version only.** Each release carries its own appcast, built from its own DMG. Sparkle only needs the newest one.
- **Release notes** come from `CHANGELOG.md` and are embedded in the appcast, so users see them in the update window.
- **Pre-releases.** A tag such as `v1.2.0-beta1` (with `VERSION` set to `1.2.0-beta1`) creates a GitHub pre-release. GitHub's `latest` link ignores pre-releases, so users keep getting the last stable appcast.
- **Cost.** The repository is public, so the minutes are free. A release takes about 15 minutes of macOS runner time.
- **Security.** The certificate lives in a temporary keychain, deleted when the runner is destroyed. The Sparkle key is passed on standard input and never written to disk. Secrets are masked in the logs.
