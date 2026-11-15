# Soaro: status

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Phase | development of the developer cleanup is planned (2026-11-15), nothing built yet; the released app is in maintenance |
| Last updated | 2026-11-15 |
| Version | 1.0.1 (tag `v1.0.1`, build 15) |

## Next action

The developer cleanup (iOS simulators, Android emulators, NuGet; Docker later) is specified in `SPEC.md` (version 0.3) and designed in `ARCHITECTURE.md` (version 0.2) with ADR 0009 (accepted: contract for tool-owned cleanup actions) and ADR 0010 (proposed: Docker, pending Test B). Next, in this order:

1. **The author:** check the simulator classification on 5 devices, check the Android list against Android Studio, decide on simulator runtimes (31.5 GB, outside the home folder; reopens ADR 0006 and 0009 if included).
2. **Test B for Docker** (the author starts Docker Desktop; nothing destructive without his confirmation). Fixes the status of ADR 0010.
3. `DESIGN.md` Part 1 (UX) is written (2026-11-15): NuGet is a row in Developer; one tool "Simulators and emulators" covers iOS and Android. `DESIGN.md` Part 2 (UI) is written too (2026-11-15): no new component; an accessibility lot goes into the shared `SelectionRow` and `ActionBar`. Decided: an accessibility slice comes before the tool (Cancel as default button, toast fade and VoiceOver announcement, a darker "supporting text" color across the app, shared selection row and action bar; see `DESIGN.md` Open points). `TESTING.md` v0.2 is written (2026-11-15): matrix for R1 to R19, the accessibility slice, test data rules (anonymised inline fixtures, no default runner for destructive paths), gates, manual checklists, definition of done. `PLAN.md` v0.1 is written (2026-11-15): 15 items, the first useful slice is SL9; the Must slices add up to 13 of the 14 working days. **Next action: `/trellis:deliver` for SL1** (Return never deletes: Cancel is the default button of the five confirmations, with injectable confirmations in the models). Pending decisions of the author: the check of the simulator classification on 5 devices (needed by SL7), the simulator runtimes (out of scope), the date of Docker Test B (SP1).

Source: the author's idea list, item 5 (`~/Projets/Perso/idees.md`).

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
