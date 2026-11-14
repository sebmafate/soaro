# Updates with Sparkle

Soaro is not on the Mac App Store, so the App Store cannot update it. [Sparkle](https://sparkle-project.org) does this job. It is the standard update framework for Mac apps outside the App Store, and it is open source.

This page explains how it works, what is already set up, and how to publish an update.

## The idea in one minute

Sparkle is a framework **inside** the app (`Soaro.app/Contents/Frameworks/Sparkle.framework`). Here is what happens when someone uses Soaro:

1. **The app reads a feed.** Once a day, Soaro downloads one small public file, the **appcast** (`https://soaro.app/appcast.xml`). It is a list of versions.
2. **The app compares versions.** Each entry in the appcast has a version number. If one is newer than the installed one, Sparkle offers the update.
3. **The user agrees.** Sparkle shows its own window with the version and the release notes.
4. **Sparkle downloads the new DMG** from the address in the appcast (a GitHub release).
5. **Sparkle checks the download.** The update must have a valid signature made with **my private key**. The matching public key is inside the installed app. If the check fails, nothing is installed.
6. **Sparkle installs it.** It quits Soaro, replaces the app, and opens the new version.

So, to publish an update, I do three things: build a new signed DMG, upload it to GitHub Releases, and add one entry to the appcast.

## Two different signatures

This confuses many people at first. There are two signatures, and they do different jobs.

| | Apple signature | Sparkle signature |
| --- | --- | --- |
| **Name** | Developer ID and notarization | EdDSA |
| **Made with** | My Apple Developer certificate | A key pair made by Sparkle |
| **Checked by** | macOS (Gatekeeper), when you open the app | Sparkle, before it installs an update |
| **Answers** | "Is this app from an identified developer, and was it scanned by Apple?" | "Does this update come from the same person who made the app I have?" |

The Sparkle signature protects users if someone takes control of the download server: without my private key, they cannot make an update that the app accepts.

## The EdDSA keys

- The **public key** is in `Info.plist` (`SUPublicEDKey`). It is not secret. It is set in `scripts/build-app.sh`.
- The **private key** is in the login keychain of the Mac that publishes updates. It is **secret**.

> **If the private key is lost, existing installations can never be updated automatically again.** Their app only trusts that key. Users would have to download a new version by hand.

Back it up once, and keep the file in a password manager:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x soaro-sparkle-private-key
```

To restore it on another Mac: `generate_keys -f soaro-sparkle-private-key`. Never commit this file.

## What is already set up

| Item | Where |
| --- | --- |
| Sparkle dependency | `Package.swift` (exact version) |
| Updater code | `Sources/Soaro/Updater.swift` |
| Settings: automatic check and "Check for updates..." | `Sources/Soaro/Views/SettingsView.swift` |
| `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` | `scripts/build-app.sh` (written in `Info.plist`) |
| Framework embedding and signing | `scripts/build-app.sh` |
| DMG and appcast generation | `scripts/release.sh` |

Sparkle only starts if the app has a feed URL and a public key. That is true for an app built by `scripts/build-app.sh`, and false for `swift run` or the tests.

## Publishing an update

The full procedure is in [releasing.md](releasing.md). In short:

1. Change the number in `VERSION` and write the changes in `CHANGELOG.md`.
2. Run `scripts/release.sh --notarize`. It builds, signs, makes the DMG, sends it to Apple for notarization, and generates the appcast.
3. Create the GitHub release `vX.Y.Z` and upload the DMG.
4. Put `build/release/appcast.xml` on the website (`soaro.app/appcast.xml`).

Order matters: upload the DMG **before** you publish the appcast. Otherwise users are offered an update that does not exist yet.

## Version numbers

Sparkle compares `CFBundleVersion`, which is the **build number**. `scripts/build-app.sh` sets it to the number of commits in the repository, so it always goes up. The visible version (`CFBundleShortVersionString`) comes from the `VERSION` file.

## Privacy

Sparkle sends no system profile (`SUEnableSystemProfiling` is off). The request for the appcast carries the usual HTTP data, like the app name and version in the user agent, and the IP address that any web request has. Nothing else.

## Testing an update

1. Build version `1.0.0` and install it.
2. Raise `VERSION` to `1.0.1`, run `scripts/release.sh` and keep the DMG and the appcast.
3. Serve them locally and temporarily point `FEED_URL` in `scripts/build-app.sh` to your local address.
4. In the installed app, choose "Check for updates...".

Sparkle's logs appear in Console.app (filter on the process name `Soaro`).

## Good to know

- **Delta updates** (small patches instead of a full download) are possible with `generate_appcast`. They are not used yet: the DMG is only about 3 MB.
- **Phased or beta channels** exist in Sparkle. They are not used yet.
- **Menu bar apps and windows.** Sparkle opens its own window. Soaro has no Dock icon, so check during testing that this window comes to the front. This is not verified yet.
