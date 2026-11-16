# Soaro: status

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Phase | development of the developer cleanup is under way (SL1, SL2, SL3 and SL7 merged, SL8 done on its branch, 2026-11-16); the released app is in maintenance |
| Last updated | 2026-11-16 |
| Version | 1.0.1 (tag `v1.0.1`, build 15) |

## Next action

The developer cleanup (iOS simulators, Android emulators, NuGet; Docker later) is specified in `SPEC.md` (version 0.3) and designed in `ARCHITECTURE.md` (version 0.2) with ADR 0009 (accepted: contract for tool-owned cleanup actions) and ADR 0010 (proposed: Docker, pending Test B). Next, in this order:

1. **The author:** check the simulator classification on 5 devices, check the Android list against Android Studio, decide on simulator runtimes (31.5 GB, outside the home folder; reopens ADR 0006 and 0009 if included).
2. **Test B for Docker** (the author starts Docker Desktop; nothing destructive without his confirmation). Fixes the status of ADR 0010.
3. `DESIGN.md` Part 1 (UX) is written (2026-11-15): NuGet is a row in Developer; one tool "Simulators and emulators" covers iOS and Android. `DESIGN.md` Part 2 (UI) is written too (2026-11-15): no new component; an accessibility lot goes into the shared `SelectionRow` and `ActionBar`. Decided: an accessibility slice comes before the tool (Cancel as default button, toast fade and VoiceOver announcement, a darker "supporting text" color across the app, shared selection row and action bar; see `DESIGN.md` Open points). `TESTING.md` v0.2 is written (2026-11-15): matrix for R1 to R19, the accessibility slice, test data rules (anonymised inline fixtures, no default runner for destructive paths), gates, manual checklists, definition of done. `PLAN.md` v0.1 is written (2026-11-15): 15 items, the first useful slice is SL9; the Must slices add up to 13 of the 14 working days. SL1 (Return never deletes) is done and merged (pull request #6, 2026-11-16): Cancel is the default button of the five confirmations, and the four cleanup models take an injectable confirmation. SL7 (iOS simulators in `--scan`, read-only) is merged (pull request #9), and so are SL1, SL2 and SL3. SL8 (the tool "Simulators and emulators", read-only) is done on its branch `slice/SL8-simulators-tool-readonly`. **Next action: the author's 5-device check of the classification (blocking merge gate of the SL8 pull request), then SL9 (remove simulators, the first useful slice); SL6 (NuGet) only needs SL1 and can start at any time.** Pending items for the author, all kept:

- Check the simulator classification on 5 devices (**blocking merge gate of SL8**): confirm or change the 60-day default (provisional, `DeviceSuggestions.defaultLimitDays`; `Soaro --scan` prints the days since last use of every listed device, and for an older copy the name, system and UDID of the kept device). Five devices: one pre-selected as inactive (more than 60 days), the dated device not pre-selected closest to 60 days, one older copy with its kept device, one with an unknown date, the largest one not pre-selected. If the threshold changes it is one line (`defaultLimitDays`), plus the boundary tests and the documents.
- Decide on simulator runtimes (31.5 GB, outside the home folder; reopens ADR 0006 and 0009 if included).
- Choose the date of Docker Test B (SP1).
- Check by hand that Return cancels and Escape also cancels a confirmation (SL1; demo mode, English and French; never click the destructive button).
- Review the 17 French strings completed by SL2.
- Check the update 1.0.0 to 1.0.1 from inside the app, and that Sparkle's window comes to the front (`docs/updates.md`).

Source: the author's idea list, item 5 (`~/Projets/Perso/idees.md`).

## Where we are

- Done: 1.0.0 and 1.0.1 published on GitHub Releases. Signed with Developer ID, notarized, updated through Sparkle. Website live on `soaro.app` (Cloudflare Pages) and serving the appcast through a redirect to the latest release. Nine languages. 410 tests in 53 suites pass on the SL8 branch (298 on `main` after SL1, SL2, SL3 and SL7, plus 112 of SL8).
- In progress: SL8 is done on its branch, awaiting review, the 5-device check and merge. SL1, SL2, SL3 and SL7 are merged (pull requests #6, #7, #8 and #9). SL2 added the network allowlist test, the catalog completeness test and the opt-in defaults test, and completed 17 French strings (to review by the author). SL3 shares `SelectionRow` and `ActionBar` (`Views/SelectionComponents.swift`) with the colour tokens in `Views/DesignTokens.swift`, and added one string in nine languages (`%@, not selectable`, AI-assisted, to review by the author).
- To check by hand (the author, SL3), never clicking a real destructive button: (1) VoiceOver reads the item name and "selected" / "not selected" on the three tools (Inactive projects, Large files, Uninstaller related files); (2) the check measures at least 24 x 24 pt in the Accessibility Inspector; (3) System Settings > Accessibility > Display > Increase Contrast switches the Delete and Uninstall fill to #B71C1C; (4) Return does nothing in the lists; (5) Digital Color Meter on the Delete button shows #D32F2F (the tinted style may modulate it: report if not); (6) carried over from SL1: Return then Escape in a real confirmation (English and French).
- To check by hand (the author, SL8), never clicking a destructive button (Delete is disabled anyway): (1) the Tools row "Simulators and emulators" is visible, and `SOARO_SECTION=cleanup:simulators` opens the tool; (2) the spinner text, the rows, the sizes filling in (note the total time; the count matches `--scan`); (3) the limit menu 30 / 60 / 90 / 180 changes the checks at once; (4) VoiceOver: each device row is one element (name, system, size, reason, state), the running row reads "not selectable", and in Large files and Inactive projects the name is read once with Show in Finder offered as an action; (5) Full Keyboard Access reaches every control, Space toggles, Return does nothing; (6) Increase Contrast, text size, light and dark, panel and window, German and Japanese (truncation hits the name, never the size); (7) `SOARO_DEMO=1` and `scripts/make-screenshots.sh` produce the tool screenshots with made-up devices; (8) review the new AI-assisted translations (20 strings, listed in the pull request).
- To verify by the author: the update 1.0.0 to 1.0.1 from inside the app, and that Sparkle's window comes to the front for a menu bar app without Dock icon (`docs/updates.md`).

## Risks and blockers

- Temperatures, fans and power use private Apple interfaces (HID, SMC) and can break on a new macOS version (ADR 0005).
- `AppState.swift` (773 lines) concentrates timing, history, actions and notifications.
- The package builds in Swift 5 language mode; strict concurrency is not enabled.
- Translations other than English and French were made with AI help and are not reviewed by native speakers.
- Release 1.0.0 is still published although it lacks Liquid Glass and translations (see CHANGELOG 1.0.1). Decision pending: keep, mark as pre-release, or delete.
- Success is defined as donations covering at least the Apple developer account (author's answer, to confirm); no kill criterion is set yet.
