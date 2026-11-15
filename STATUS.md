# Soaro: status

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Phase | maintenance (released), preparing the next feature |
| Last updated | 2026-11-15 |
| Version | 1.0.1 (tag `v1.0.1`, build 15) |

## Next action

The developer cleanup (iOS simulators, Android emulators, NuGet, SwiftPM; Docker later) is specified in `SPEC.md` (2026-11-15, version 0.2, status validated for the Must scope). Next: the author checks the simulator classification on 5 devices and the Android list against Android Studio and decides on simulator runtimes (31.5 GB, outside the home folder), then `/trellis:architect` (a new ADR completing ADR 0006 for actions that are not file deletion), then Test B for Docker. Source: the author's idea list, item 5 (`~/Projets/Perso/idees.md`).

## Where we are

- Done: 1.0.0 and 1.0.1 published on GitHub Releases. Signed with Developer ID, notarized, updated through Sparkle. Website live on `soaro.app` (Cloudflare Pages) and serving the appcast through a redirect to the latest release. Nine languages. 135 tests pass.
- In progress: nothing.
- To verify by the author: the update 1.0.0 to 1.0.1 from inside the app, and that Sparkle's window comes to the front for a menu bar app without Dock icon (`docs/updates.md`).

## Risks and blockers

- Temperatures, fans and power use private Apple interfaces (HID, SMC) and can break on a new macOS version (ADR 0005).
- `AppState.swift` (773 lines) concentrates timing, history, actions and notifications.
- The package builds in Swift 5 language mode; strict concurrency is not enabled.
- Translations other than English and French were made with AI help and are not reviewed by native speakers.
- Release 1.0.0 is still published although it lacks Liquid Glass and translations (see CHANGELOG 1.0.1). Decision pending: keep, mark as pre-release, or delete.
- Success is defined as donations covering at least the Apple developer account (author's answer, to confirm); no kill criterion is set yet.
