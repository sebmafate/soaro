# Releasing

This is the **manual** procedure to publish a new version, from the maintainer's Mac (it needs the Apple certificate and the Sparkle private key). The same steps run automatically on GitHub when a tag is pushed: see [ci-release.md](ci-release.md).

## One-time setup

| What | How |
| --- | --- |
| **Developer ID certificate** | "Developer ID Application: Sebastien Ferrand (K8H46QQHGX)", installed in the login keychain. The first `codesign` asks for access to its private key: choose "Always Allow" |
| **Notary profile** | `xcrun notarytool store-credentials "soaro-notary" --apple-id <id> --team-id K8H46QQHGX`. It asks for an app-specific password. It is stored in the keychain, never in a file |
| **Sparkle key pair** | Made with `generate_keys`. Back up the private key (see [updates.md](updates.md#the-eddsa-keys)) |
| **Sparkle tools** | `swift package resolve --disable-keychain` downloads them into `.build/artifacts/sparkle/Sparkle/bin` |

If `swift package resolve` hangs on the Sparkle download, use `--disable-keychain`. It happens when the keychain has two entries for github.com.

## Steps

1. **Check the code.** `swift test` must pass.
2. **Choose the version.** Edit `VERSION` (for example `1.1.0`). Follow [semantic versioning](https://semver.org).
3. **Write the changelog.** Move the "Unreleased" notes of `CHANGELOG.md` under the new version and date.
4. **Commit and tag.**
   ```bash
   git commit -am "Version 1.1.0"
   git tag v1.1.0
   ```
5. **Build the release.**
   ```bash
   scripts/release.sh              # signed DMG, no notarization (to inspect)
   scripts/release.sh --notarize   # same, then sends it to Apple and staples the ticket
   ```
   Notarization usually takes a few minutes. If it fails, read the log with `xcrun notarytool log <submission-id> --keychain-profile soaro-notary`.
6. **Check the DMG.** Open it on a Mac, or use a clean user account, and run the app. `spctl -a -t open --context context:primary-signature -vv build/release/Soaro-1.1.0.dmg` must say "accepted" and "Notarized Developer ID".
7. **Publish the binary.**
   ```bash
   git push github main --tags
   gh release create v1.1.0 build/release/Soaro-1.1.0.dmg --title "Soaro 1.1.0" --notes-file <notes>
   ```
8. **Publish the appcast.** Add it to the same release: `gh release upload v1.1.0 build/release/appcast.xml`. `soaro.app/appcast.xml` redirects to the latest release's copy (see [website.md](website.md)).
9. **Test the update** from the previous version with "Check for updates...".

## What the script does

`scripts/release.sh` runs four steps:

1. `scripts/build-app.sh` with the Developer ID: it signs every nested component (Sparkle's helpers, then the framework, then the app) with the hardened runtime and a secure timestamp.
2. It makes a compressed DMG with an `Applications` shortcut and signs it.
3. With `--notarize` only, it sends the DMG to Apple, waits for the result, and staples the ticket to the DMG. Stapling lets Gatekeeper accept the app **offline**.
4. It runs Sparkle's `generate_appcast`, which signs the DMG with the EdDSA key and writes `appcast.xml`.

## If something goes wrong

- **`errSecInternalComponent` while signing.** The keychain is locked or `codesign` was denied access to the key. Unlock the keychain, or approve the access prompt.
- **Notarization is "Invalid".** Read the log. The usual causes are a component that is not signed with the hardened runtime, or a missing secure timestamp.
- **Users do not see the update.** Check that the appcast is reachable, that its version number (`sparkle:version`) is higher than the installed build number, and that the DMG URL answers.
- **Pulling a bad release.** Edit the appcast of the latest release (or release a fixed version): remove the bad entry and upload it again with `gh release upload --clobber`. Existing users who already updated stay on it: publish a fixed, higher version.
