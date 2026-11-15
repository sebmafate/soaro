# 0003. Sparkle updates; the appcast is a release asset reached through a redirect

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | Sparkle: before 1.0.0. Appcast as a release asset: 2026-11-15 (made during the first CI release; the author accepted it) |
| Drives from | an app outside the App Store needs its own update path |

## Context

Without the App Store there is no automatic update. Updates must be authenticated: a compromised download server must not be able to push a malicious update. The `main` branch is protected by a ruleset (pull request required, signed commits), so a workflow cannot commit the feed to the repository. Evidence: `docs/updates.md`, `Package.swift` (Sparkle 2.10.1, exact), `Updater.swift`, `.github/workflows/release.yml`, `site/_redirects`.

## Options considered

### Option A: no auto-update (manual download)
- For: nothing to maintain. Against: users stay on old versions.

### Option B: Sparkle with EdDSA signatures; appcast committed to `site/`
- For: the feed is a normal file on the website. Against: the CI would have to push to a protected `main` (rejected, 2026-11-15).

### Option C: Sparkle with the appcast attached to each GitHub release; `soaro.app/appcast.xml` redirects to `releases/latest/download/appcast.xml`
- For: no push to `main`; the DMG and appcast are published together; pre-releases are ignored by `latest`. Against: the feed depends on GitHub's redirect and on the Cloudflare redirect rule.

## Decision

Option C. The app reads `https://soaro.app/appcast.xml` (`SUFeedURL`); each release carries its own appcast, signed with the EdDSA key kept in a GitHub secret and in the author's keychain.

## Consequences

- Good: fully automated release; update authenticity does not depend on the hosting.
- Bad: the appcast holds only the latest version; losing the EdDSA private key means installed apps can never auto-update again (`docs/updates.md`).
- Risks: the redirect breaks (the site is down); the first release shipped before the site existed, so 1.0.0 showed an update error until the site was deployed.

## Revisit when

Several versions or channels (beta) must coexist in the feed, or the hosting changes.

## Open points

- Sparkle's window behaviour for a menu bar app without Dock icon is unverified.
