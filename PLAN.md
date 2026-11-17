# Soaro developer cleanup: plan

| | |
| --- | --- |
| Status | draft |
| Version | 0.1 |
| Date | 2026-11-15 |
| Based on | `SPEC.md` v0.3, `ARCHITECTURE.md` v0.2 (ADR 0009, 0010), `DESIGN.md` v0.1, `TESTING.md` v0.2 |

## Approach

Soaro is an adopted project: only the **remaining work** is planned (requirements R1 to R19, the accessibility work decided on 2026-11-15, the Docker test and release 1.1). The baseline is the existing suite (135 tests, green); there is no walking skeleton to build.

Order: first what protects the user and the tests that follow (Return never deletes, repository guards), then the shared components the new screen needs, then the tool from the simplest piece to the riskiest: NuGet, a read-only look at iOS simulators (command line, then screen), removal of simulators, then Android (list, then removal, with the two spikes of risks 5 and 6). The accessibility work that nothing depends on (SL4, SL5) comes after the first useful slice, and the Docker part waits for its test.

**First useful slice: SL9** (simulators can be removed). SL6 (NuGet) is an earlier quick win. Deliberately after it: Android, the system images, Docker.

**Time box (kill criterion 3 of the spec):** the Must scope (R1 to R9 and R16 to R18) is capped at **14 working days**. Assumed sizes: S is about 1 day, M about 2 days. The Must slices (SL1, SL2, SL6 to SL11) add up to **13 days**, which leaves 1 day of margin that the two Android spikes may use. **SL3 is not counted** in the cap, and neither are SL4 and SL5 (accessibility decisions of the author, not R1 to R19; confirmed 2026-11-15). If the Must slices pass 14 days, stop and cut to iOS simulators and Android devices only. Days actually spent are written in the table below.

## Slices

Sizes: S (about a day), M (about two days), L (split it).

| ID | Slice | Size | Depends on | Counts in the 14 days | Days spent | Status |
| --- | --- | --- | --- | --- | --- | --- |
| SL1 | Return never deletes | S | | yes | under 0.1 (measured: about 14 min of agent time, 13:03 to 13:17 on 2026-11-16, of which about 10 min waiting on a stuck package download; QA review and the author's manual Return/Escape check not included) | done |
| SL2 | Repository guards: network allowlist, translation catalog | S | | yes | 0.25 | done |
| SL3 | Shared selection list components and the destructive button | M | SL1 | no | under 0.1 (measured from the first to the last commit timestamp, about 6 min of agent time on 2026-11-16, 13:59:52 to 14:05:57; QA review and the author's manual checks not included) | done |
| SL6 | NuGet packages row | S | SL1 | yes | 0.25 (measured from the first commit at 10:53 to the last (the review fixes) at about 11:26 on 2026-11-17, about 33 min of agent time, rounded up to a quarter day; the reading before the first commit is not counted; the author's manual checks not included). Running total without SL9: under 0.85 + 0.25 = under 1.1 of the 14 days; with SL9 (0.25, merged): under 1.35 | done |
| SL7 | iOS simulators in `--scan` | M | SL1, SL2 | yes | 0.25 (measured: 18 min of agent time from the first commit at 14:24 to the last at 14:42 on 2026-11-16, rounded up to a quarter day; about 2 min of it waiting on real scans for the manual checks; the reading before the first commit is not counted; QA review and the author's 5-device check not included). Running total: under 0.1 + 0.25 + 0.25 = under 0.6 of the 14 days | done |
| SL8 | The tool "Simulators and emulators", read-only | M | SL3, SL7 | yes | 0.25 (measured from the first commit at 15:35 to the last (the documents) at 16:21 on 2026-11-16, about 46 min of agent time, rounded up to a quarter day; the reading before the first commit is not counted; about 10 min of it were lost to a test run that hung, see the notes; QA review and the author's manual checks not included). Running total: under 0.1 + 0.25 + 0.25 + 0.25 = under 0.85 of the 14 days | done |
| SL9 | Remove simulators (**first useful slice**) | M | SL8 | yes | 0.25 (measured from the first commit at 10:12 to the last (the documents of the fix round after the review and the QA) at 10:35 on 2026-11-17, about 23 min of agent time, rounded up to a quarter day; the reading before the first commit is not counted; QA review and the author's manual checks not included). Running total: under 0.1 + 0.25 + 0.25 + 0.25 + 0.25 = under 1.1 of the 14 days | done |
| SL4 | Darker supporting text across the app | M | SL3 | no | | todo |
| SL5 | Toast: Reduce Motion and VoiceOver | S | | no | | todo |
| SL10 | Android emulators in the tool | M | SL8 | yes | 0.25 (measured from the first commit at 12:59 to the last (the documents) at 13:17 on 2026-11-17, about 18 min of agent time, rounded up to a quarter day; the reading before the first commit is not counted; QA review and the author's manual checks not included). Running total: under 1.35 + 0.25 = under 1.6 of the 14 days | done |
| SL11 | Remove Android emulators | M | SL9, SL10 | yes | | todo |
| SL12 | Android system images (Should) | S | SL11 | no | | todo |
| SP1 | Docker Test B (spike, the author starts Docker Desktop) | | | no | | todo |
| SL13 | Docker (Should, coarse; only if SP1 passes) | M | SP1, SL8 | no | | todo |
| SL14 | Release 1.1 | S | the slices done | no | | todo |

Statuses: `todo`, `in progress`, `done`, `dropped`. The slice IDs follow the order of discussion, not the order of execution; the execution order is the order of the table.

## Slice details

### SL1: Return never deletes

- **Goal**: pressing Return on a confirmation never deletes anything; Cancel is the default button.
- **Serves**: R8 (extended 2026-11-15); `DESIGN.md` accessibility rule "Confirmation default".
- **Components**: `AppState.confirm` and its five callers (cleanup, Trash, inactive projects, uninstall, login items); the cleanup models.
- **Acceptance criteria**
  - [x] The alert is built separately from being shown, and its default button is Cancel for all five callers.
  - [x] The `critical` flag still sets only the alert style.
  - [x] Each cleanup model receives its confirmation as an injectable parameter with a default; a test with a "cancel" confirmation shows that nothing is deleted (inactive projects, large files, uninstaller, login items).
  - [x] The confirmation text of existing tools is unchanged.
- **Tests**: unit (alert configuration; models with an injected confirmation).
- **Notes**: touches published behaviour: a `CHANGELOG` line. Enables the "cancelling deletes nothing" tests of later slices. Done 2026-11-16: `AppState.makeConfirmationAlert` and `AppState.confirmationResult`; the type `ConfirmHandler` and `SystemConfirmation.ask` (in `CleanupModels.swift`); the four models take `confirm:` plus an initial-state parameter (`files`, `artifacts`, `apps`/`current`, `loginItems`; empty by default) as the test seam. The cleanup action of `AppState.cleanup` is not injected (out of scope): it gets the Cancel default through the shared builder only. The login-item test is weak by nature (removal is asynchronous). Still to check by hand: Return then Escape in a real alert (English and French).

### SL2: Repository guards

- **Goal**: two tests that protect the privacy promise and the translations for every later slice.
- **Serves**: R9, R12; `TESTING.md` T6, T11.
- **Components**: the test target only (reads the sources and `Sources/Soaro/Resources/Localizable.xcstrings` through `#filePath`).
- **Acceptance criteria**
  - [x] A test fails if a source file other than `PublicIPService.swift` references `URLSession` or `NWConnection`. (`NetworkAllowlistTests`; made to fail on purpose with a throwaway file, then removed.)
  - [x] A test fails if a catalog key lacks one of the nine languages, or if the placeholders (`%@`, `%lld`, `%1$@`, `%%`) differ between languages. (`TranslationCatalogTests`, on `Localizable.xcstrings` and `InfoPlist.xcstrings`.)
  - [x] Both tests pass on the current code, or the real gaps they find are listed (fixed here if small). (17 gaps found, all in French, all fixed in one commit; see Notes.)
  - [x] Where the defaults of the two optional network features are readable from a test, a test shows they are off. (`OptInDefaultsTests`, registered defaults only.)
- **Tests**: unit (repository level).
- **Notes**: if the catalog test finds existing gaps, list them rather than widening this slice.
  - Gaps found on the real catalog (17, all French): 16 keys had no French entry (`1 h`, `24 h`, `Application`, `CPU`, `GPU`, `Internet`, `Max`, `Min`, `Orange`, `Signal`, `Soaro`, `Style`, `VPN`, `Wi-Fi`, `Xcode iOS DeviceSupport`, `normal`); the French text of the battery explanation wrote `100 %%` where the key has no placeholder, so the app showed `100 %%` (checked on the built bundle). Fixed in one commit: the 16 French entries equal the English key (what the app already displayed through the fallback), and `%%` became `%`. These French strings are AI-assisted and flagged for the author's review.
  - The placeholder rule treats a key without placeholder as never formatted: `100 % zu` in German is not a gap there. Checked for `String(localized:)`; `Text("...")` was not checked.
  - Days spent (0.25): measured from the first to the last SL2 commit timestamp, rounded up to a quarter day.
  - Out of reach of the allowlist: `Data(contentsOf:)`, `Process`/`curl`, `NWPathMonitor`, Sparkle, and the optional `/sbin/ping` of `NetworkSampler.ping`.

### SL3: Shared selection list components and the destructive button

- **Goal**: `SelectionRow` and `ActionBar` are shared, readable by VoiceOver and keyboard friendly, so the new screen and the existing tools use the same parts.
- **Serves**: `DESIGN.md` Part 2; R8.
- **Components**: `CleanupToolViews.swift` (the two components move out of `private`), new `SelectionComponents.swift` and `DesignTokens.swift`. `Components.swift` is not touched (SL6 edits `CleanupRow` there).
- **Acceptance criteria**
  - [x] The selection button names the item: label = the name, value = "Selected" / "Not selected" (`SelectionRowAccessibilityTests`), wired in Inactive projects, Large files and the Uninstaller (related files).
  - [ ] Manual, pending the author's check: VoiceOver reads the name on the three tools (for example "web-shop, selected").
  - [x] The check has a hit target of at least 24 x 24 pt (constant `SelectionMetrics.minimumTargetSize`, test `checkTargetIsAtLeast24Points`; a weak check by nature).
  - [ ] Manual, pending the author's check: the target measures at least 24 x 24 pt in the Accessibility Inspector.
  - [x] New variant "unavailable" (icon `minus.circle` plus a text reason; the toggle is never called) and new "busy" state of the action bar exist and are used nowhere yet except in previews (`PreviewProvider` previews in `SelectionComponents.swift`; they exist by compile, pure-function tests and review).
  - [x] The destructive button uses #D32F2F (and #B71C1C with Increase Contrast): `ActionBarTint.danger`, tested as values. Never a default button, no keyboard shortcut (source scan test, R8).
  - [ ] Manual, pending the author's check: Digital Color Meter on the real Delete button shows #D32F2F (the tinted `.borderedProminent` style may modulate the fill); Increase Contrast switches to #B71C1C; Return does nothing in the list.
  - [x] A test computes the contrast of the defined colors: white on danger-fill 4.98 : 1 and on the deeper red 6.57 : 1 (`ContrastTests`); text-supporting at least 4.5 : 1 on both reference backgrounds, with and without Increase Contrast.
  - [x] The existing tool tests still pass (208 tests, up from 172).
- **Tests**: unit (contrast, pure label/value function, tint, enabled state, catalog key); existing suites; manual VoiceOver pass on the three tools.
- **Notes**: also defines the color token "text-supporting", used by the new rows; its use across the app is SL4. Done 2026-11-16.
  - The shared components are in `Views/SelectionComponents.swift` and the tokens in `Views/DesignTokens.swift`, not in `Components.swift` (SL6 edits `CleanupRow` there).
  - Three tools are affected, not two: the Uninstaller also uses `SelectionRow` (related files) and `ActionBar(destructive: true)` ("Uninstall"). The author's VoiceOver pass covers all three.
  - Text-supporting is defined as pure black (light) or pure white (dark) at an **absolute** alpha of 0.56 (0.70 with Increase Contrast). `Color.primary.opacity(0.56)` would start from `labelColor` (about 85 % alpha) and give about 3.6 : 1 on white, which fails; the ratios of `DESIGN.md` (4.95 and 6.1) only hold with the absolute alpha. So SL4's contrast criterion reduces to "applied everywhere": the token is tested here.
  - `SelectionRow` takes a required `name`; an empty name falls back to the state alone. A blank or empty reason still makes the row unavailable (only `nil` is selectable). New string `%@, not selectable` in nine languages (AI-assisted, flagged for the author's review).
  - Increase Contrast on the dark reference background: #B71C1C against #1E1E1E is about 2.5 : 1 (below the 3 : 1 of a non-text component), while the standard #D32F2F gives 3.35 : 1. Not required by the slice; reported to the author (the label inside the button stays at 6.57 : 1).
  - Rows become slightly taller (24 pt check). The reveal-in-Finder button is a second control in each row, so VoiceOver may read the name twice; merging the controls is for SL8.
  - VoiceOver may read the name twice (button label + visible text); merging rows is for SL8; the author's VoiceOver pass should check it.
  - Days spent (under 0.1): measured from the first to the last SL3 commit timestamp (same method as SL1 and SL2).

### SL6: NuGet packages row

- **Goal**: the author cleans the 13 GB of the NuGet cache from the Developer list, after a confirmation.
- **Serves**: R1, R2, R13; J1, J2; S1, S3.
- **Components**: `CleanupKind` (new `nugetCache`, `~/.nuget/packages`), `CleanupService` (home folder as a parameter), `CleanupRow`, demo data.
- **Acceptance criteria**
  - [x] The row "NuGet packages" appears in Developer only if the folder exists, with its size (`CleanupKindTests` on a fake tree, `CleanupListRulesTests`; the real size read by `--scan`: 13.7 GB against `du -sk` 13,377,848 KB, the same number).
  - [x] Clean asks for a confirmation with the size; Cancel (default) deletes nothing (`CacheCleanupFlowTests`: exact text, a cancelling confirmation gives zero `clean` calls; the Cancel-first alert is the SL1 builder, already tested).
  - [x] After the cleanup the toast shows the space really freed (`NuGetCleanupTests`: before minus after per item; `CacheCleanupFlowTests`: the toast text).
  - [x] NuGet is not part of the quick clean, and the quick clean total excludes it (`CleanupKindTests`, `CleanupListRulesTests`, `EngineTests`).
  - [x] A test shows that "App caches" includes `org.swift.swiftpm` and never `~/Library/org.swift.swiftpm` (`CleanupServiceHomeTests`).
  - [ ] Manual: on the author's Mac about 13 GB are freed (within 10 % of `df`). **Pending the author** (a real, destructive clean is the author's decision; the agent did not run it).
  - [x] Demo mode shows the row without touching the disk (`DemoData` has 13.1 GB for NuGet; confirming in demo mode deletes nothing: `CacheCleanupFlowTests`, and in the four tools `DemoModeToolsTests`). Looked at on screen: not done, pending the author.
- **Tests**: unit (kind, items, size on a fake tree with an injected home, quick clean); disk tests in the `.soaro-test-<uuid>` sandbox; manual. 57 tests added (480 in 59 suites on its own branch, 559 in 63 once merged with SL9: 40 in the first round, 15 in the first review round, 2 in the second).
- **Notes**: strings added in nine languages (the catalog test of SL2 checks them): one new key, "NuGet packages", AI-assisted wording to review by the author. The detail line reuses the npm key. Done 2026-11-17:
  - **Route**: plain file deletion through `CleanupService.clean` (ADR 0009 Option C, ADR 0006), no `dotnet nuget locals`, no runner. `NUGET_PACKAGES` and `globalPackagesFolder` are not read; the HTTP cache and the plugin cache are not covered (backlog).
  - **Home parameter**: `directory(for:)`, `items(for:)`, `size(of:)` and `clean(_:)` take `home` with the real home as default; `isSafeToDelete` stays tied to the real home, so a fake home gives "listed, every deletion refused".
  - **Freed space**: before minus after for each top-level item (the measure is a parameter of `CleanupService.clean`, so partial credit is tested without the disk order), for every cache kind. It differs from before only when a deletion fails partway (an item that fails now adds what was really removed; `removeItem` stops at the first error, in directory order). The on-disk partial-failure test does not depend on the directory order; the strict partial credit is proven with the injected measure.
  - **Pure rules**: `CleanupKind.visibleDeveloperKinds(sizes:)` and `CleanupKind.quickCleanTotal(sizes:)`, used by `CleanupTab`, `AppState.quickCleanReclaimable` and `RecommendationEngine`.
  - **Demo fix**: before SL6, confirming under `SOARO_DEMO=1` deleted, trashed or removed real things, because the demo data is built from the real home folder and no action had a demo check. The new `CacheCleanupFlow` (confirm, then clean, then toast) has a demo branch that never calls `clean`; it fixes every cleanup row. `AppState.cleanup` passes the confirmation, the real `CleanupService.clean` and the demo flag. The flow takes one parameter more than the brief lists, `willStart`, so that the rows are marked busy only after a confirmation (and never in demo mode). **Review round (the author decided to fix it in this pull request):** the four tools got the same guard: `LargeFilesModel.trashSelected`, `DevArtifactsModel.removeSelected`, `UninstallerModel.uninstall` and `StartupModel.remove` still ask the same confirmation in demo mode, but nothing is trashed, deleted or run (no Trash, no AppleScript); the rows leave the in-memory list and the toast shows the made-up size (the same texts as a real success). Also found and fixed: the startup switch (`StartupModel.setEnabled`) ran `launchctl enable/disable/bootout` for the made-up labels (now only the switch changes), and `AppState.quitApp` ran `terminate()` on **real running apps** matched by the demo paths (Safari, Xcode, Mail, Music, Notes: the Overview "Quit" button could really quit them; now the toast is shown and nothing is quit). `AppState` takes the demo flag, the confirmation, the clean action and the quit action as init parameters with the real ones as defaults, so `AppState.cleanup` and `quitApp` are tested in demo mode (`AppStateDemoTests`); `StartupModel` takes its two real actions the same way. The tools read their demo flag from an init parameter (default `DemoMode.isEnabled`); `scan`, `load` and `select` use it too. Nothing else reachable in demo mode deletes: the rest of the `Process`, `removeItem`, `trashItem` and AppleScript uses are the samplers (read-only), `LegacyMigration` (already skipped in demo mode), `emptyTrash` (only through `CleanupService.clean`, now behind the flow), and `AppUninstaller.uninstall` (only through the model). `AppUninstaller.isRunning` still reads the real process list in demo mode before the confirmation (read-only, behaviour unchanged).
  - **Symlinks**: a `packages` folder that is a symbolic link is read as "folder not accessible" (`contentsOfDirectory(at:)` does not follow it), so the row is hidden and nothing is touched; a symlinked package inside is refused by `isSafeToDelete` (its target is outside the home folder).
  - **Scan cost**: the NuGet size (70,873 files, 13.7 GB on the author's Mac) joins the 30-minute scan; `du -sk` of it takes about 3 s, the whole `--scan` about 42 s with the simulators.
  - **No "in use" check** for NuGet (as npm, Gradle and Cargo): a restore or build running during the clean may fail and must be run again.

### SL7: iOS simulators in `--scan`

- **Goal**: `Soaro --scan` prints the simulators with their real size, reason and suggestion, read only.
- **Serves**: R3, R6, R7; ADR 0009; `TESTING.md` T8, T9.
- **Components**: new `CommandRunner` (protocol, real and fake), `ToolLocator` (`/usr/bin/xcrun`), `SimulatorScanner` (pure parsing of `simctl list devices -j`), `DeviceSuggestions` (pure), the `--scan` mode.
- **Acceptance criteria**
  - [x] The real runner kills a process at the time limit, bounds its output and refuses a relative path or a shell (integration tests on `/bin/echo`, `/bin/sleep`, `/usr/bin/yes`; `CommandRunnerIntegrationTests`, 9 tests, run 5 times in a row without a failure).
  - [x] The parser reads a recorded, anonymised `simctl` output (contract test) and survives malformed JSON, a missing tool and a non-zero exit (the section is empty, nothing crashes). The fixture is anonymised by hand from a real recording made once on the author's Mac (read-only, outside the repository, deleted afterwards). The recording held only `Shutdown`, available, iOS devices: the `Booted` device, the unavailable one (`availabilityError`) and the watchOS runtime in the fixture were added by hand from the known format of the tool.
  - [x] The suggestion function pre-selects devices inactive beyond the limit (default 60 days) and older copies of the same model and runtime; devices under 100 MB are counted, not listed; the limit is a parameter.
  - [x] Sizes use the allocated space (a sparse file test on `CleanupService.allocatedSize` and on the scanner).
  - [x] Manual (run by the agent on the author's Mac, 2026-11-16, counts only): the list printed by `--scan` matches `xcrun simctl list devices` (same device count and same UDID set between the JSON and the text output of `simctl`; every listed device matches on name, runtime, state, availability, date presence and whole days; listed plus small equals the total).
- **Tests**: unit, integration, contract (90 tests added by SL7, 262 on its own branch; 298 once merged with SL3).
- **Notes**: scanners and removers take the runner with **no default value**; the real runner is built in `Diagnostics.scan` and, since SL8, in `CleanupTab` (and nowhere else). Read-only: nothing is removed. Done 2026-11-16: `CommandRunner` (protocol, outcome type), `RealCommandRunner` (the only new use of `Process`), `ToolLocator` (`/usr/bin/xcrun`), `SimulatorScanner` (parsing, then `scan` with allocated sizes), `DeviceSuggestions`, `SimulatorReport` (pure text of the `--scan` section), the fake runner in the test target. The key read for the last use is `lastUsedAt` (16 of 42 devices on the author's Mac carry it; the others are "unknown" and never pre-selected). Manual results: the simulators section took 16.5 s and 23.2 s in two runs of the debug build (42 devices, about 45 GB; `simctl list` itself under 1 s), so SL8 should use **progressive sizes** (above the 10 s threshold). The allocated total is 1.02 times `du -sk` of the devices folder (within 10 %, R7). Missing `xcrun` (M4) was not tried on the real Mac (not safe to do without changing the system): covered by unit tests only. The author's check of the classification on 5 devices was done on 2026-11-17: OK. The limit stays a parameter and 60 days is confirmed (one named constant, `DeviceSuggestions.defaultLimitDays`); `--scan` prints the days since last use of every listed device so the author can judge. Not in SL7, kept open: the decision on simulator runtimes (31.5 GB). Known limit: grandchild processes of a killed tool are not killed. Not changed: `CHANGELOG.md` (the section is a developer mode, no user-facing change).

### SL8: The tool "Simulators and emulators", read-only

- **Goal**: the author opens the tool, sees the simulators with reasons, and the right ones are pre-selected; nothing can be deleted yet.
- **Serves**: R3, R6; J1, J3 (steps 1 and 2), J4; S1, S2.
- **Components**: `CleanupRoute` (one new route), `CleanupTab` (the row in Tools, hidden without Xcode), the model and the view of the tool, demo data.
- **Acceptance criteria**
  - [x] The row "Simulators and emulators" appears in Tools only if the simulator tool is found (unit: `SimulatorToolDetectorTests`, `SimulatorsScreenTests.toolsRowVisibilityIsAPureFunctionOfDetectionAndDemo`). Manual, pending the author: the row is visible on his Mac; `SOARO_SECTION=cleanup:simulators` opens the tool.
  - [x] The scan starts on opening; a spinner reads "Looking for simulators and emulators…" (unit: `SimulatorsModelTests`). Manual, pending the author: the spinner, the rows and the sizes filling in (total time noted, count equal to `--scan`).
  - [x] The group "iOS Simulators" is sorted by size once the sizes are in, each row shows a reason ("inactive for 66 d", "older copy of “name”, used 4 d ago"), pre-selected rows are checked, the footer counts the hidden small devices (unit: `SimulatorsProgressiveSizesTests`, `SimulatorsSelectionTests`, `SimulatorPresentationTests`). Manual, pending the author: the look in panel and window, light and dark.
  - [x] The limit menu (30, 60, 90, 180 days) recomputes the pre-selection at once, with no scan and no runner call (J4); at a limit with nothing to suggest the banner "Nothing to suggest at 60 days…" shows (unit: `SimulatorsSelectionTests`).
  - [x] States: no device ("No simulator or emulator found."), unreadable tool ("Could not read the iOS Simulators."), tool slow ("Xcode’s simulator service did not answer. Try again in a moment."). There is only one group until SL10, so "the other group stays usable" means here that the header, the limit menu and "Scan again" stay usable (unit: `SimulatorsModelTests`).
  - [x] The Delete button was not available in SL8: disabled, empty action, no keyboard shortcut (unit: `SimulatorsScreenTests`, `ActionBarTests.noViewBindsAKeyboardShortcut`). It is live since SL9; the no-shortcut rule is unchanged.
  - [x] Demo mode works for the screenshots: made-up devices, no runner call, no measure, nothing read or written (unit: `SimulatorsDemoTests`). Manual, pending the author: `SOARO_DEMO=1` and `scripts/make-screenshots.sh` produce the tool screenshots.
  - [x] **BLOCKING manual check before merge: Full Keyboard Access on the shared `SelectionRow`. Done by the author, 2026-11-17, OK.** The row uses `.accessibilityElement(children: .ignore)` to read as one VoiceOver element, which may hide the checkbox and the "Show in Finder" button from Full Keyboard Access. Check that Space toggles the checkbox and that Show in Finder is reachable, on Large files, Inactive projects **and** the Uninstaller leftover rows. If not, the row needs another variant (to decide with the author; not verifiable without the GUI, so nothing was changed).
  - [x] **Merge gate:** the 5-device check of the classification. Done by the author, 2026-11-17, OK: the 60-day default is confirmed (`DeviceSuggestions.defaultLimitDays` is no longer provisional).
  - [ ] Manual, pending the author: VoiceOver (one element per row, running row "not selectable", Show in Finder as an action in Large files and Inactive projects), Full Keyboard Access, Increase Contrast, text size, German and Japanese (truncation hits the name, never the size), review of the new translations.
- **Tests**: unit (model states with a fake runner, progressive sizes, selection, demo, presentation, detector, screen rules): 125 tests added by SL8, 423 tests in 53 suites; manual (panel and window, light and dark).
- **Notes**: done 2026-11-16 in 11 tasks (T1 to T11 of the brief).
  - **Tool detection (clears prerequisite 1 of the SL7 review).** `SimulatorToolDetector` looks at the disk and launches nothing: the devices folder (`~/Library/Developer/CoreSimulator/Devices`) exists, or the `simctl` that `xcrun` will actually run is an executable regular file. `xcrun` follows the active developer folder, so when the link `/var/db/xcode_select_link` (what `xcode-select -s` writes) is a symbolic link, the only candidate is its destination (a relative one is resolved against `/var/db`) plus `/usr/bin/simctl`, with no fallback; only when the link is missing, `xcode-select`'s own fallback is used: `/Applications/Xcode.app/Contents/Developer/usr/bin/simctl`, then each `/Applications/Xcode*.app`, sorted by name. It never reads `DEVELOPER_DIR` or the PATH. The runner is called only when a `simctl` is on the disk **and** `/usr/bin/xcrun` is found (`ToolLocator.simulatorXcrunPath`); otherwise the result is "tool not found" and nothing is launched. Xcode copies under `~/Applications` are not detected (accepted). With the Command Line Tools selected while Xcode is installed, the active `simctl` is absent, so nothing is launched and the neutral message appears (the row still shows if the devices folder exists). Fixed after the review of the first SL8 version, which let the launch through whenever any `simctl` existed. `Diagnostics.scan` follows the same gate; its line is now "simulator tool not found". Checked once on the author's Mac, read-only: `/var/db/xcode_select_link` is a symbolic link.
  - **Kept device (clears prerequisite 2).** `DeviceSuggestions.Row.keptDevice` is the first device of the group in the existing ranking, even if small, unlisted or running. The reason names it: "older copy of “name”, used N d ago" / "used today" / "which is running". `--scan` prints `older copy of <name> (<system>, <udid>)` to make the 5-device check easy.
  - **Progressive sizes.** The list appears as soon as `simctl list` answers (rows in listing order: name, system, UDID; size "…"); the sizes are then measured one device at a time off the main actor and applied as they arrive; a device measured under 100,000,000 bytes leaves the list and the selection at once and joins the footer; when the last size arrives the rows are sorted by size (ties: name, UDID). Back and "Scan again" cancel the measuring; a size that arrives after a cancel is never applied. A scan cancelled by Back is not kept (the next opening rescans). Real run on the author's Mac (debug build, `--scan`): 42 devices, 16.6 s for the whole scan (command plus sizes), the same order of magnitude as SL7. Before the sizes are known the pre-selection comes from the dates and the grouping (unknown size counts as "big enough"); ties between equal dates may differ from the final `suggest` and are realigned on the next limit change or rescan.
  - **Group label and system.** One group "iOS Simulators" for all Apple platforms; each row shows its system ("iOS 26.2", "watchOS 11.2", "tvOS 18.2"); the platform `xrOS` is shown as `visionOS`; an unreadable identifier is "Unknown system", never the raw identifier. The word "runtime" does not appear in the interface.
  - **Decisions of this brief.** Unavailable devices are selectable and flagged ("unavailable: system not installed"), with no extra pre-selection rule; a running device is the SL3 unavailable row ("Running · quit it first"), reused by SL9; the limit is not remembered between sessions (backlog item stays open); a limit change replaces manual picks (J4); no "Show in Finder" in the new screen; no plural forms in the footer ("1 small devices" is accepted: the catalog test rejects variations); the tool subtitle mentions Android before SL10 (nothing is released before SL14). `EmptyHint` gained an optional `color` so the new screen can use the supporting-text token (a small additive change to `Components.swift`; SL4 restyles the app).
  - **Shared row (T9).** `SelectionRow` reads as one VoiceOver element (name, details, value); the details come from the call site. In Large files and Inactive projects Show in Finder is still a mouse button and also a named VoiceOver action of the row. The Uninstaller related-files rows get the single-element reading too. Combined elements may not expose Show in Finder to Full Keyboard Access: manual check.
  - **Tests and hang.** The model tests use two hand-written blocking fakes (runner and `measure`) with an awaitable "started" signal; a first version blocked cooperative threads and hung the suite when run in parallel (found by repeating the filter, fixed by a non-blocking signal and `.serialized` suites; 10 runs in a row without failure).
  - **Fix round after the review (2026-11-16).** The first version let the launch through when any `simctl` existed (Command Line Tools active, Xcode installed: the screen always failed); the gate now follows the active developer folder (see above). Also: "Scan again" is disabled during the listing and a repeated trigger is ignored; already-translated messages are shown verbatim; the supporting-text style is reused; the late-size test observes the write itself; `Diagnostics.simulatorScan` is tested.
  - **Not verified by an agent:** every visual and VoiceOver item above (the app was not launched: another instance of Soaro may be running on the author's Mac, and the screenshot script stops it).

### SL9: Remove simulators (first useful slice)

- **Goal**: the author removes the pre-selected simulators, after a confirmation that says what is lost.
- **Serves**: R4, R5, R7, R8; J3; S2, S3.
- **Components**: `SimulatorScanner` (removal through `simctl delete`), `SimulatorRemover` (one device after its checks), `SimulatorRemoval` (batch summary and toast text), the tool model and view, `ConfirmHandler` (`AppState.confirm` in the app).
- **Acceptance criteria**
  - [x] The confirmation names the count, the size and the loss ("apps and data … and snapshots"), and Cancel is the default (unit: `SimulatorsDeletionTests.theConfirmationNamesTheCountTheSizeAndTheLoss`, `cancellingTheConfirmationCallsNothing…`; the Cancel-first alert is the SL1 builder, `ConfirmationTests`; the button has no key: `ActionBarTests.noViewBindsAKeyboardShortcut`). Manual, pending the author: Cancel highlighted, Return deletes nothing (step 2 below).
  - [x] The fake runner receives exactly `xcrun simctl delete <udid>` (`/usr/bin/xcrun`, 60 s, 1 MiB); if the tool fails, no folder is deleted (unit: `SimulatorRemovalTests.theRunnerReceivesExactlyTheDeleteCommandWithItsLimits`, `aFailingDeleteIsReportedAndTheRealFolderStays`; source test: no `removeItem(`, `trashItem(` or `"/bin/rm"` in any `Simulator*.swift`).
  - [x] A `Booted` device is not selectable ("Running · quit it first", SL8 rule, `SimulatorsDeletionTests.aRunningDeviceCanNeverBeSelected`); a device that becomes `Booted` between the scan and the action is refused with "“iPhone 15” is running: quit it first." (unit: `aDeviceBootedAfterTheScanIsRefusedAndTheOthersAreRemoved`, `aSingleBootedTargetShowsOnlyTheRunningText`, `SimulatorRemovalOneDeviceTests`).
  - [x] After the action the list is rescanned and the toast shows the space really freed (before minus after); a partial failure shows "Devices that could not be removed: N" (unit: `afterTheConfirmationTheCallsAreScanThenRecheckAndDeletePerDeviceThenRescan`, `SimulatorRemovalSummaryTests`).
  - [x] A tool that does not answer in time shows "Xcode’s simulator service did not answer. Try again in a moment." and the batch stops (unit: `aDeleteTimeoutStopsTheBatchAndShowsTheDidNotAnswerText`, `aTimedOutRecheckStopsWithoutDeleting`).
  - [ ] Manual, pending the author: a disposable simulator (`xcrun simctl create`) is removed and is gone in Xcode; a booted simulator is refused (the six steps in the pull request).
- **Tests**: unit with a fake runner that returns successive outcomes, a recording confirmation, a scripted `measure` and temp folders inside the real home (79 tests added by SL9: 502 tests in 57 suites); manual on disposable targets.
- **Notes**: done 2026-11-17 in 8 tasks (T1 to T8 of the brief).
  - **One device, in this order** (`SimulatorScanner.remove`, synchronous, off the main actor): (1) a fresh `simctl list` (same command, 60 s and 8 MiB as SL8) right before this device's delete: listing timed out gives "timed out", any other failed listing gives "could not check", a UDID missing from the fresh list gives "already gone" (not a failure), a state other than `Shutdown` (Booted, Booting, Shutting Down, unknown) gives "running" with the device's name from the fresh list; (2) the folder (`deviceFolder(udid:home:)`) must pass `CleanupService.isSafeToDelete` (strictly inside the real home folder) or the device is "refused" and no command runs; (3) the folder is measured; (4) `xcrun simctl delete <udid>`: only if it reports removed the folder is measured again, and freed is before minus after, floored at 0. Never a fallback: if the tool fails, the folder is not touched. About 1 s per device for the re-check.
  - **Delete values**: 60 s and 1 MiB (`deleteTimeLimit`, `deleteOutputLimit`, the only values in the code). They settle the open point of ADR 0009; ARCHITECTURE records them (A8), ADR 0009 is not edited. "Removed" needs exit code 0, an ordinary exit and a non-truncated output; a runner time-out is "timed out"; every other case (non-zero exit, signal, truncated output, launch failure, refusal) is "failed". The error output is never read. An invalid UDID or a missing `xcrun` path launches nothing.
  - **Freed space (R7)**: allocated size of the device folder right before its delete minus right after (not the volume's free space, which other apps disturb). Against `df`, Time Machine local snapshots or purgeable space can keep `df` from moving: if the author's 10 % check fails, record it; the measure is not changed without a decision.
  - **Batch** (`SimulatorRemovalSummary.run`): targets in display order, cancellation checked before each one, a command already running is never interrupted. "Running", "failed", "refused" and "could not check" each count as one failure; "could not check" stops the batch and the remaining targets count as failures (so with `xcrun` gone at action time every target is a failure and nothing is launched); "timed out" (re-check or delete) stops the batch and sets a flag; "already gone" counts for neither.
  - **Toast**: parts joined with " · ". The freed part ("X freed", `Format.fileBytes`) comes first when at least one device was removed or when there is no failure and no time-out ("Zero KB freed" when everything was already gone). Then: time-out gives "Xcode’s simulator service did not answer. Try again in a moment."; otherwise exactly one failure that is a running device gives "“name” is running: quit it first."; otherwise any failure gives "Devices that could not be removed: N" (running devices included). The names are never catalog keys.
  - **Model**: `SimulatorsModel.init` takes `confirm: ConfirmHandler` **with no default** (stricter than the four older models, so a test never shows a real alert); `CleanupTab` passes `SystemConfirmation.ask`. The brief counted 8 existing call sites; there were 9 (8 in tests, 1 in `CleanupTab`). `canDelete` (a pure static function too): list shown, sizes measured, at least one device checked, no deletion running. The batch runs in a detached task (user-initiated priority) with a `CancelToken`, never in the tick; detection and the `xcrun` gate are evaluated again at action time. At the end: toast, `isDeleting = false`, then `scan()` (fresh list, new pre-selection); `deleteTask` also waits for that scan, so a test awaits one task. While deleting, `toggle`, `setLimit` and `scan` are ignored and `canScanAgain` is false.
  - **Back during a deletion**: no new target starts, the current one finishes, there is no rescan, and the phase becomes "not scanned" with the rows cleared, so the next opening rescans and never shows a stale list. The toast does not claim success: devices never tried are counted as not removed ("X freed · Devices that could not be removed: 2"), and a Back before any attempt shows no toast. If the screen is opened again before the batch ends, it reads "Deleting…" and the model remembers the scan and starts it when the batch ends.
  - **One batch for the whole process (fix round after the review)**: the model is owned by `CleanupTab`, which is destroyed when the user leaves the Cleanup tab, and the panel and the window each own a model. `SimulatorDeletionGate` (shared, injectable) is taken before a batch and freed at its end, whatever the outcome; while it is busy no model can scan or delete, so two `simctl delete` can never race on one UDID. The batch's toast and the gate release do not depend on the model, so a confirmed batch always ends with its toast even if the tab was left. A list shown by another surface may be stale afterwards; a device already gone is reported as "already gone", not as a failure. This replaced the `onChange` in `SimulatorsView`.
  - **Demo mode**: the same confirmation (so S3 can be screenshotted); if confirmed, no runner call, no measure, no detection, nothing read or written, the checked rows leave the list at once, the toast is the sum of their made-up sizes "freed", and there is no rescan.
  - **Strings**: 5 new keys in nine languages (`“%@” is running: quit it first.`, `Devices that could not be removed: %lld`, `Delete the selected devices? (%lld)`, the confirmation message, `Deleting…`), no variations; the wording is AI-assisted and to review by the author.
  - **Screen**: the ActionBar is destructive-tinted, "Delete" is enabled by `canDelete`, busy with "Deleting…" while deleting; the limit menu and "Scan again" are disabled while deleting; no shortcut or default action.
  - **Tests**: written first (each new test file failed to compile or failed before the code; T1 and T2 failed to compile for the missing API); the model tests wait on `deleteTask` and on an awaitable signal, never on a sleep; suites are `.serialized`. Checked by mutation: removing the cancellation of the delete token on Back, or the `isDeleting` guard in `toggle`, fails the deletion tests.
  - **Not verified by an agent**: the real `simctl delete` (never run, by rule), every visual item (the app was not launched: another instance of Soaro may be running and the screenshot script stops it), VoiceOver, Full Keyboard Access on the new bar.
  - **Pending the author (manual, disposable simulators only)**: the six steps of the pull request (create and boot two "Soaro Test" devices, delete them with Soaro and compare with `df -k ~` within 10 %, a booted device is refused, a device booted after the scan is refused with its name, demo mode, review of the 5 new translations).
- **Result**: after this slice the first usable version for iOS exists (success criterion S2 is reachable with NuGet and the simulators).

### SL4: Darker supporting text across the app

- **Goal**: supporting text is readable in light mode everywhere, with almost the same grey.
- **Serves**: `DESIGN.md` accessibility decision (not R1 to R19).
- **Components**: the 69 uses of `.secondary` for text in 11 view files, `SectionHeader`, the two informative `.tertiary` texts (`CleanupToolViews.swift:87`, `NetworkTab.swift:106`).
- **Acceptance criteria**
  - [ ] Text that used `.secondary` uses text-supporting; icons keep `.secondary`.
  - [ ] `SectionHeader` is `.caption` in text-supporting; the two `.tertiary` texts use text-supporting; chevrons stay tertiary.
  - [ ] Text-supporting is applied everywhere through the token of SL3 (`DesignTokens`, absolute alpha 0.56 / 0.70); its contrast is already tested in `ContrastTests` (SL3).
  - [ ] `--snapshot` screenshots of every tab compared with the previous ones: only the grey changes.
- **Tests**: unit (contrast); manual screenshot comparison.
- **Notes**: a `CHANGELOG` line ("slightly darker grey for supporting text").

### SL5: Toast: Reduce Motion and VoiceOver

- **Goal**: toasts respect Reduce Motion and are announced by VoiceOver.
- **Serves**: `DESIGN.md` accessibility rules.
- **Components**: `PopoverView` and `MainWindow` (the toast views), `AppState.showToast`.
- **Acceptance criteria**
  - [ ] With Reduce Motion on, the toast fades in and out without the slide.
  - [ ] With VoiceOver on, the toast message is announced when it appears.
  - [ ] Behaviour with the setting off is unchanged.
- **Tests**: manual (no useful unit test).
- **Notes**: applies to every toast of the app.

### SL10: Android emulators in the tool

- **Goal**: the Android group appears in the tool with the author's six virtual devices.
- **Serves**: R16, R18, R6; J1, J3 (steps 1 and 2); S2.
- **Components**: `ToolLocator` (Android SDK: variables, then `~/Library/Android/sdk`), `AndroidEmulatorScanner` (the `.ini` and `config.ini` files, running detection from the process list), `DeviceSuggestions` (shared), the tool model and view, `--scan`.
- **Acceptance criteria**
  - [x] With the variable set, the default path, or nothing, the locator behaves as specified (tests with an injected environment and home); without an SDK the Android group is hidden and iOS still works (unit: `AndroidSDKLocatorTests`, `AndroidListingTests.noSdkMeansNothingAndNothingIsLaunchedEvenWithAvds`, `AndroidGroupModelTests.withoutAnSdkTheAndroidGroupIsHiddenAndTheRunnerCallsAreTheIosOnes`, `SimulatorsScreenTests` layout and tools row).
  - [x] On a fake `~/.android/avd` in a temporary home: name, image, size and last-used date (from files) are read (unit: `AndroidAVDParsingTests`, `AndroidAVDListingTests` in a `.soaro-test-<uuid>` sandbox, size through the injected `measure` in `AndroidGroupModelTests`, `AndroidDeviceSuggestionsTests` (in `DeviceSuggestionsTests.swift`) for the suggestion).
  - [x] A running AVD is recognised from a recorded `ps` line containing `-avd <name>` and is not selectable (unit: `AndroidRunningDetectionTests` on an anonymised hand-written line, `AndroidGroupModelTests.aRunningAvdIsNeverSelectedAndToggleDoesNothing`, `AndroidPresentationTests`). The line is hand-written from the known format, not recorded from a real emulator: see the spike below).
  - [ ] Manual: the list matches Android Studio (6 AVD); with `ANDROID_SDK_ROOT` pointing to a missing folder, the Android group is hidden.
  - [ ] **Spike (risk 6):** one real running emulator is detected and refused; the result is written in `ARCHITECTURE.md`.
  - [ ] The best "last used" signal is chosen and written down (spec open question). **Proposed in SL10, pending the author:** the newest modification date among `hardware-qemu.ini`, `emulator-user.ini`, `userdata-qemu.img.qcow2`, `userdata-qemu.img`, `cache.img.qcow2` and `snapshots/default_boot/snapshot.pb` (one constant, `AndroidEmulatorScanner.lastUsedFiles`); `--scan` prints the date of each listed file per AVD and the winner. **Suspect (QA round 1):** see the notes.
- **Tests**: unit, contract (`config.ini`, `ps`), manual.
- **Notes**: done 2026-11-17 in 12 tasks (T1 to T12 of the brief), 175 tests added (734 tests in 72 suites, with the QA and review round fixes). The Android group shows no removal yet.
  - **SDK rule** (`ToolLocator.androidSDK`, pure, no launch, no PATH): of `ANDROID_SDK_ROOT` then `ANDROID_HOME`, the first one that is set and not empty decides: an absolute path to an existing directory is the SDK, anything else (missing folder, a file, a relative path) gives no SDK, **with no fallback** (the plan's manual step: a missing `ANDROID_SDK_ROOT` hides the group). Only when neither is set: `<home>/Library/Android/sdk`. The result carries its source (`ANDROID_SDK_ROOT`, `ANDROID_HOME`, default), printed by `--scan`. An app opened from the Finder does not see these variables, so only the default folder works there.
  - **Last-used signal (proposal, pending the author)**: the newest content-modification date among the files in `lastUsedFiles` (above), relative to the AVD folder, missing files skipped; none present means "unknown", never pre-selected. `config.ini`, `multiinstance.lock` and the `<name>.ini` are excluded on purpose (Android Studio writes the first two without the device being used; ADR 0009 says the lock exists even when nothing runs). Alternatives kept in the brief: the `.avd` folder date, or `config.ini`.
  - **Running detection** (`runningAVDNames`): exactly `/bin/ps -axww -o command=`, time limit **10 s**, output cap **4 MiB** (`processListTimeLimit`, `processListOutputLimit`, the only values in the code), standard error never read. A token `-avd` followed by a valid name, or a token `@<name>`, counts (the name is kept as written; the match with an AVD ignores case, APFS does, and is never a prefix). **"Process list unavailable"** (no `ps` path, time-out, launch failure, refusal, non-zero exit, a signal, truncated output) means the group is **unreadable**: "Could not read the Android emulators." and no row, because a running state that cannot be checked is not offered. An empty output is an empty set, not unavailable. `ps` is only looked up and called when an SDK exists and at least one AVD is registered.
  - **AVD folders** (`listAVDs`, read-only): `<home>/.android/avd/<name>.ini` with a valid name (`[A-Za-z0-9._-]`, not `.` or `..`) registers a device; a `.avd` folder without its `.ini` is ignored. The folder is the first existing directory among `path=` (absolute only), `path.rel` (against `<home>/.android`) and `<home>/.android/avd/<name>.avd`; it must be **strictly inside the home** after standardising and resolving symlinks, else the AVD is skipped (an existing folder outside the home is skipped, it does not fall through to the next candidate). `.ini` and `config.ini` are read up to 1 MiB, ordinary files only; past that, unreadable or not UTF-8 they count as missing. The name shown is `avd.ini.displayname` or the AVD name; the system is `API N` from `image.sysdir.1`, else "Unknown system". An absent `avd` folder is "no device", a folder that cannot be listed is "could not read".
  - **No "older copy" rule for Android** (R16 asks only for the idle threshold): `DeviceSuggestions.suggestAndroid` shares the limit, the 100 MB threshold and the whole-days rule with iOS; running and undated devices are never pre-selected by the rule. A 54-day AVD is listed but not pre-selected at the 60-day default (nothing changed). One comparator (`AndroidDevice.isOrderedBefore`, display name without case, then AVD name) orders the listing, the suggestion tie-break and the rows while sizes are measured.
  - **Model**: `SimulatorsModel` has an Android group (own phase, rows, sizes and selection keyed by AVD name) next to iOS. One detached task lists sequentially (`simctl list`, then `ps`), then sizes are measured one folder at a time, iOS rows first, then Android rows; each group is sorted by size when its own sizes are in. The group is **hidden** with no SDK; the **iOS group is hidden** when neither the devices folder nor the active `simctl` exists (it used to say "Could not read the iOS Simulators."); a devices folder with no `simctl` still gives that message. `environment` is an init parameter **with no default** (GitHub's macOS runners set `ANDROID_HOME`); `locateXcrun` became `locateTool` and is also called with `processListCandidates`. The 15 call sites changed (14 tests, `CleanupTab`).
  - **Android is NOT pre-selected in SL10 (author's decision after the review: "do not pre-select Android before SL11").** The rows are listed with size and "inactive for N d", the pure rule still computes `isPreSelected` (so `--scan` prints `pre-selected: inactive` followed by a note that the app does not pre-select Android until SL11), but the model checks nothing on a scan or a limit change. One switch, `DeviceSuggestions.androidPreselectionEnabled = false`, read by `SimulatorsModel` (init parameter `androidPreselects`, so tests can turn it on); SL11 flips it with the deletion. A running device stays unselectable; the user may check a non-running Android row by hand. The banner "Nothing to suggest…" ignores a group whose pre-selection is off (Android alone shows no banner; iOS listed with nothing pre-selected still does). **SL11 entry condition:** the author settles the last-used signal (`lastUsedFiles`, suspect: the files carry near-identical ages) BEFORE SL11 turns the Android pre-selection on (`DeviceSuggestions.androidPreselectionEnabled`). The row says "inactive for N d" as a fact: once the signal is settled the wording may need "about" (no string change now).
  - **Delete is disabled while any Android row is checked** (`canDelete` takes `androidSelectedCount`; targets stay iOS only; SL11 lifts it). Since nothing is checked for the user, only a deliberate check of an Android row disables it; the demo opens with Delete usable for iOS. Nothing on screen explains it (no existing string fits).
  - **Screen**: `SimulatorsScreen.layout(ios:android:)` (pure) chooses a spinner, "No simulator or emulator found.", the full-screen message of the only failed group, or the sections iOS then Android; a failed group beside a listed one shows its header and message and the other stays usable. The tools row also shows when only an Android SDK is found (looked up off the main actor with the process environment).
  - **Demo mode**: three made-up AVDs (`DemoData.androidEmulators`), shown at once with no detection, `ps` or measure.
  - **Strings**: 3 new keys in nine languages (`API %@`, `Android emulators`, `Could not read the Android emulators.`), no variations; the wording is AI-assisted and to review by the author.
  - **Existing tests changed** (setup only, no expectation weakened): the 14 `SimulatorsModel(` call sites (new `environment: [:]`, `locateXcrun:` renamed `locateTool:`); the two `canDelete` rule tests (new `androidSelectedCount: 0`); the three `showsToolsRow` tests (new `androidSDK:`); the demo-deletion tests first unchecked the pre-selected demo AVD, and were put back unchanged once Android stopped being pre-selected (review round). No SL8 test needed a new detection for the hidden iOS rule.
  - **Real Mac, read-only** (`Soaro --scan`, counts only): 6 AVDs listed, none running; every date came from `emulator-user.ini`, between 0 and 6 days ago, so none is pre-selected at 60 days; the Android section took 0.1 s. **The signal is SUSPECT.** Observation, per-file read-only `--scan` on the author's Mac (ages only, no names): on all 6 AVDs `hardware-qemu.ini`, `emulator-user.ini` and `userdata-qemu.img.qcow2` have the SAME age, between 0 and 6 days; `userdata-qemu.img` is 25 to 56 days old; `cache.img.qcow2` is 3 or 25 days old; `snapshots/default_boot/snapshot.pb`, where it exists, is 0 to 8 days old. Two explanations fit: the devices really ran in the last days (then the dates are right and nothing is idle), or one tool touched several files at once (Android Studio, a backup or a sync), which would make the newest date meaningless. These dates contradict the earlier A6 evidence (five AVDs sharing one older date, 2026-10-23; the 11 GB AVD last written about 54 days before the spec of 2026-11-15). Dropping `emulator-user.ini` alone would change no AVD's date, because two other files carry the same age. The direction is safe (a recent date means nothing is pre-selected), but the suggestion can be useless.
  - **Question for the author:** which files should count as "used" (for example only `userdata-qemu.img`, or only the data and snapshot files), or were the devices really used in the last days? `lastUsedFiles` stays unchanged until he decides (one constant).
  - **QA round 1 (accept with notes)**: `--scan` now prints per AVD the date (YYYY-MM-DD) and age of each existing listed file (an indented `files:` line, `none` when no file exists; the listing returns all per-file dates); the relative-`path=` test can now fail; a model test covers a scan asked during a deletion with the Android group. **Delete disabled while an Android row is checked: nothing on screen says why**, and no existing string fits, so it is left as is (decision 5, pending the author; a new string would be needed). The footer text still mentions iOS older copies (backlog).
  - **Review round (pr-reviewer, comments)**: (1) Android is not pre-selected before SL11 (above); (2) an AVD folder is accepted only if, resolved, it is strictly inside the home, its name ends in `.avd` and it holds a regular `config.ini` (the strictest rule that fits `avdmanager` and Android Studio layouts; a `.ini` pointing at `~/Documents` or `../x` is skipped, with no fall-through to another candidate; a relocated `*.avd` inside the home is accepted; one outside the home, such as one moved by `ANDROID_AVD_HOME`, stays out of scope), and two `.ini` for one folder give one row (the first by name); (3) the running match ignores case (APFS does), still the whole name; (5) one shared order comparator, `--scan` looks up the SDK before `ps`, and `--scan` prints a count of skipped registrations (folder missing, outside the home or not an AVD folder; counts only). Translation review note: zh-Hans "Android 仿真器" for "Android emulators" (the existing iOS strings use 模拟器: to align or keep).
  - **Review round 2 (reviewer and QA, last round)**: the explanation footer ("…are pre-selected…") is shown only under the iOS section when iOS is listed (`SimulatorsScreen.footers`, pure; the hidden-small-devices count stays under the last section, existing strings only, no new key), so with Android alone no explanation is shown; two `.ini` for one folder give one row (the first by name) that carries the other names as `aliases`, and the row is running if ANY of them is in the process list; the skipped count survives an unavailable `ps` and is printed in that case too; four more folder-rule tests (a symlink named `X.avd` to a non-`.avd` folder, an uppercase `.AVD` suffix (rejected: errs on the safe side), a trailing slash in `path=` (accepted), a `path.rel` through a symlink ending outside the home). **SL11 entry condition:** the deletion must still refuse any running registration (a folder is refused if the primary name OR any alias runs), and must re-check right before acting.
  - **Layout fixes after the author's test of the build**: list footers (simulators, inactive projects, startup items) are no longer cut to one line (`lineLimit(nil)` and `fixedSize(horizontal: false, vertical: true)`); Cleanup and Settings no longer sit in a 640 pt column centred in the pane, so their scroll bar is at the window's edge (the Cleanup tools list caps its column inside the scroll view, as `page` does; the tool screens and the Settings form follow the pane width; the popover, 430 pt wide, is unchanged). Not verified without a GUI: the look of the wide lists and of the wrapped footers.
  - **Not verified by an agent**: any real running emulator (never started, by rule), the screen itself (the app was not launched), VoiceOver, the three translations by a native reader.
  - **Pending the author** (see STATUS): the list against Android Studio (6 AVD), the `ANDROID_SDK_ROOT` check, the spike of risk 6 with a disposable AVD, the choice of the last-used signal, the demo check, the review of the 3 translations.

### SL11: Remove Android emulators

- **Goal**: the author removes virtual devices from the tool.
- **Serves**: R17, R8; J3; S2, S3.
- **Components**: `AndroidEmulatorScanner` (pair removal), the tool model and view.
- **Acceptance criteria**
  - [ ] Only the `.ini` and the `.avd` folder are removed; a neighbouring AVD stays; an `.ini` whose `path=` is outside the home folder is refused.
  - [ ] A running AVD is refused, including one started between the scan and the action.
  - [ ] The confirmation says the device and its snapshots are lost; Cancel is the default; the toast shows the real freed space.
  - [ ] **Spike (risk 5):** a disposable AVD is created and removed with `avdmanager` and by the pair route; what is left on disk is compared, and the result is written in `ARCHITECTURE.md` (and ADR 0009 is revisited if `avdmanager` removes more).
  - [ ] Manual: the removed AVD is gone in Android Studio and in `avdmanager list avd`.
- **Tests**: unit, manual on a disposable AVD.
- **Notes**: if the Must scope is past 14 days here, apply kill criterion 3.

### SL12: Android system images (Should)

- **Goal**: unused system images can be removed, with the download warning.
- **Serves**: R19; S2b.
- **Components**: an Android image scanner, the tool view (group "Android system images").
- **Acceptance criteria**
  - [ ] Each image shows its size and the AVD that uses it; an image in use is not selectable ("used by ap26").
  - [ ] An image no device uses is pre-selected; the confirmation says it must be downloaded again (with the size).
  - [ ] Matching by `image.sysdir.1` is tested; manual check on the author's six images.
- **Tests**: unit, manual.

### SP1: Docker Test B (spike)

- **Goal**: decide ADR 0010 with a measurement.
- **Serves**: R10, R11; kill criterion 1.
- **Acceptance criteria**
  - [ ] With Docker Desktop started by the author, free space (`df`), the allocated size of `Docker.raw` and `docker system df` are noted before and after a build-cache prune and an untagged-image prune, with no volumes and no reclaim container, each prune confirmed by the author.
  - [ ] ADR 0010 becomes `accepted` if at least half of the announced space comes back, or `deprecated` (and R10, R11 are dropped) otherwise.
- **Notes**: no date: it needs the author.

### SL13: Docker (Should, coarse)

- Only if SP1 passes. The tool for Docker (usage, build cache and untagged images, honest space returned), with the command allowlist of ADR 0010 and a fake runner. To be detailed after SP1.

### SL14: Release 1.1

- Version number and `CHANGELOG` (Keep a Changelog: Return never deletes, supporting text, new cleaners), translations of the new strings, the manual checklists of `TESTING.md`, then `docs/releasing.md` (every outward step confirmed). To be detailed when the other slices are done.

## Coverage

| Requirement | Priority | Slices |
| --- | --- | --- |
| R1 | Must | SL6 |
| R2 | Covered | SL6 (test) |
| R3 | Must | SL7, SL8 |
| R4 | Must | SL9 |
| R5 | Must | SL9 |
| R6 | Must | SL7, SL8, SL10 |
| R7 | Must | SL7, SL9 |
| R8 | Must | SL1, SL3, SL9, SL11 |
| R9 | Must | SL2 |
| R10 | Should | SP1, SL13 |
| R11 | Should | SP1, SL13 |
| R12 | Should | SL2, and each slice that adds strings |
| R13 | Should | SL6 |
| R14 | Could | backlog |
| R15 | Could | backlog (SL13 if a tester appears) |
| R16 | Must | SL10 |
| R17 | Must | SL11 |
| R18 | Must | SL10 |
| R19 | Should | SL12 |

Slices with no requirement (stated): SL3, SL4, SL5 (the accessibility decisions of 2026-11-15, recorded in `DESIGN.md`), SP1 (spike), SL14 (release).

States from `DESIGN.md`: S1 (first use, tool absent, busy, error) in SL6 and SL8; S2 scanning, no device, nothing pre-selected, platform unreadable in SL8 and SL10; device running, deleting, partial failure, tool too slow in SL9 and SL11; S2b in SL12; S3 in SL9 and SL11. **Deferred:** S4 Docker (SL13). No error or empty state is forgotten.

## Backlog (not planned)

- Launch at login (`SettingsView.swift`, `SMAppService.mainApp.register()` and `unregister()`) is not guarded in demo mode: toggling it under `SOARO_DEMO=1` changes the real login item of the app. Pre-existing, outside Cleanup; the author decides.
- The real-action default parameters of `AppState` and `StartupModel` differ from the "no default for destructive runners" rule of `TESTING.md`; the author is asked to accept this explicitly (reason written in `TESTING.md`).
- The toast " (N items in use were skipped)" also counts items that `isSafeToDelete` refuses (for example a symlink to outside the home), where "in use" is not the cause. Wording kept as is (review of SL6, nit); to reword with a translation round if it ever confuses.
- Could requirements: R14 (recommendations that point to the new cleaners), R15 (OrbStack, needs a tester).
- Simulator runtimes (31.5 GB outside the home folder): out of scope until the author decides; reopens ADR 0006 and 0009 together.
- Whether the limit "Inactive for more than" is remembered between sessions.
- A local pre-commit hook for `swift test` (a habit today).
- Refactor of the four copies of the process helper onto the shared `CommandRunner`.

## Change log

| Date | Change | Reason |
| --- | --- | --- |
| 2026-11-15 | Plan created from the spec, architecture, design and test strategy. SL4 and SL5 placed after SL9 and kept out of the 14-day count | Author's decision during the slice step: protect the time box; SL3 stays before the tool because the screen depends on it |
| 2026-11-16 | SL3 done on its branch: components in new files, not in `Components.swift`; the Uninstaller is the third tool affected; SL4's contrast criterion reduces to "applied everywhere" | The token is defined and tested in SL3 with an absolute alpha; `Components.swift` is left to SL6 |
| 2026-11-16 | SL7 started before the author's check of the classification on 5 devices. The check moves to before SL8 shows a default limit, and before the release at the latest | The limit is a parameter of the suggestion function, so SL7 does not depend on the check (author's instruction) |
| 2026-11-16 | SL8 done on its branch. Progressive sizes (backlog item) done as planned; tool detection by disk only, as the SL7 review asked. The 5-device check is the blocking merge gate of the SL8 pull request | Author's instruction in the SL8 brief |
| 2026-11-17 | SL6 done on its branch. Plain deletion route (ADR 0009 Option C). Demo mode no longer deletes real files when a cleanup is confirmed (fix of a defect found while adding the demo row). Freed space is now before minus after per item | The SL6 brief, decisions 1, 4 and 5; the real clean on the author's Mac stays a manual decision |
| 2026-11-17 | SL6 review round: demo mode also guarded in the four tools, the startup switch and the Overview "Quit" button (the last one could quit real apps). Injectable demo flag and actions on `AppState`, `StartupModel` and the tool models | Pull request review; the author decided to fix it in the SL6 pull request |
| 2026-11-17 | SL9 done on its branch. The 5-device check and the Full Keyboard Access check of SL8 were done by the author (OK): the 60-day default is confirmed. The delete values (60 s, 1 MiB) settle the open point of ADR 0009 and are recorded in ARCHITECTURE | Author's facts in the SL9 brief; no decision changed |
| 2026-11-17 | SL10 done on its branch. Android emulators are listed in the tool (read-only); the last-used signal is a proposal (newest date among the files the emulator writes) that the author confirms with `--scan`; no SDK means no Android group; Delete stays disabled while an Android row is checked until SL11; the iOS group is hidden without Xcode | The SL10 brief, decisions 1 to 9; no requirement changed |
