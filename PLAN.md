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
| SL3 | Shared selection list components and the destructive button | M | SL1 | no | | todo |
| SL6 | NuGet packages row | S | SL1 | yes | | todo |
| SL7 | iOS simulators in `--scan` | M | SL1, SL2 | yes | 0.25 (measured: 18 min of agent time from the first commit at 14:24 to the last at 14:42 on 2026-11-16, rounded up to a quarter day; about 2 min of it waiting on real scans for the manual checks; the reading before the first commit is not counted; QA review and the author's 5-device check not included). Running total: under 0.1 + 0.25 + 0.25 = under 0.6 of the 14 days | done |
| SL8 | The tool "Simulators and emulators", read-only | M | SL3, SL7 | yes | | todo |
| SL9 | Remove simulators (**first useful slice**) | M | SL8 | yes | | todo |
| SL4 | Darker supporting text across the app | M | SL3 | no | | todo |
| SL5 | Toast: Reduce Motion and VoiceOver | S | | no | | todo |
| SL10 | Android emulators in the tool | M | SL8 | yes | | todo |
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
- **Components**: `CleanupToolViews.swift` (the two components move out of `private`), `Components.swift`.
- **Acceptance criteria**
  - [ ] The selection button names the device or item, for example "web-shop, selected" (VoiceOver), in the existing "Inactive projects" and "Large files" tools.
  - [ ] The check has a hit target of at least 24 x 24 pt.
  - [ ] New variant "unavailable" (icon `minus.circle` plus a text reason) and new "busy" state of the action bar exist and are used nowhere yet except in previews.
  - [ ] The destructive button uses #D32F2F (and #B71C1C with Increase Contrast).
  - [ ] A test computes the contrast of the defined colors: white on danger-fill at least 4.5 : 1.
  - [ ] The existing tool tests still pass.
- **Tests**: unit (contrast), existing suites; manual VoiceOver pass on the two existing tools.
- **Notes**: also defines the color token "text-supporting" (primary at 56 %, 70 % with Increase Contrast), used by the new rows; its use across the app is SL4.

### SL6: NuGet packages row

- **Goal**: the author cleans the 13 GB of the NuGet cache from the Developer list, after a confirmation.
- **Serves**: R1, R2, R13; J1, J2; S1, S3.
- **Components**: `CleanupKind` (new `nugetCache`, `~/.nuget/packages`), `CleanupService` (home folder as a parameter), `CleanupRow`, demo data.
- **Acceptance criteria**
  - [ ] The row "NuGet packages" appears in Developer only if the folder exists, with its size.
  - [ ] Clean asks for a confirmation with the size; Cancel (default) deletes nothing.
  - [ ] After the cleanup the toast shows the space really freed.
  - [ ] NuGet is not part of the quick clean, and the quick clean total excludes it.
  - [ ] A test shows that "App caches" includes `org.swift.swiftpm` and never `~/Library/org.swift.swiftpm`.
  - [ ] Manual: on the author's Mac about 13 GB are freed (within 10 % of `df`).
  - [ ] Demo mode shows the row without touching the disk.
- **Tests**: unit (kind, items, size on a fake tree with an injected home, quick clean); manual.
- **Notes**: strings added in nine languages (the catalog test of SL2 checks them).

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
- **Tests**: unit, integration, contract (83 tests added: 172 to 255).
- **Notes**: scanners and removers take the runner with **no default value**; the real runner is built only in `Diagnostics.scan`. Read-only: nothing is removed. Done 2026-11-16: `CommandRunner` (protocol, outcome type), `RealCommandRunner` (the only new use of `Process`), `ToolLocator` (`/usr/bin/xcrun`), `SimulatorScanner` (parsing, then `scan` with allocated sizes), `DeviceSuggestions`, `SimulatorReport` (pure text of the `--scan` section), the fake runner in the test target. The key read for the last use is `lastUsedAt` (16 of 42 devices on the author's Mac carry it; the others are "unknown" and never pre-selected). Manual results: the simulators section took 16.5 s and 23.2 s in two runs of the debug build (42 devices, about 45 GB; `simctl list` itself under 1 s), so SL8 should use **progressive sizes** (above the 10 s threshold). The allocated total is 1.02 times `du -sk` of the devices folder (within 10 %, R7). Missing `xcrun` (M4) was not tried on the real Mac (not safe to do without changing the system): covered by unit tests only. **Still open: the author's check of the classification on 5 devices.** The limit stays a parameter and 60 days stays provisional (one named constant, `DeviceSuggestions.defaultLimitDays`); `--scan` prints the days since last use of every listed device so the author can judge. Not in SL7, kept open: the decision on simulator runtimes (31.5 GB). Known limit: grandchild processes of a killed tool are not killed. Not changed: `CHANGELOG.md` (the section is a developer mode, no user-facing change).

### SL8: The tool "Simulators and emulators", read-only

- **Goal**: the author opens the tool, sees the simulators with reasons, and the right ones are pre-selected; nothing can be deleted yet.
- **Serves**: R3, R6; J1, J3 (steps 1 and 2), J4; S1, S2.
- **Components**: `CleanupRoute` (one new route), `CleanupTab` (the row in Tools, hidden without Xcode), the model and the view of the tool, demo data.
- **Acceptance criteria**
  - [ ] The row "Simulators and emulators" appears in Tools only if the simulator tool is found.
  - [ ] The scan starts on opening; a spinner reads "Looking for simulators and emulators…".
  - [ ] The group "iOS Simulators" is sorted by size, each row shows a reason ("inactive for 66 d", "older copy"), pre-selected rows are checked, the footer counts the hidden small devices.
  - [ ] The limit menu recomputes the pre-selection at once (J4); at a limit with nothing to suggest, the banner "Nothing to suggest at 60 days…" shows.
  - [ ] States: no device ("No simulator or emulator found."), unreadable platform ("Could not read…") with the other group still usable.
  - [ ] The Delete button is not available yet.
  - [ ] Demo mode works for the screenshots.
- **Tests**: unit (model states with a fake runner), manual (panel and window, light and dark).
- **Notes**: if the real sizes take more than about 10 s on the author's Mac, switch to progressive sizes (`DESIGN.md` open question).

### SL9: Remove simulators (first useful slice)

- **Goal**: the author removes the pre-selected simulators, after a confirmation that says what is lost.
- **Serves**: R4, R5, R7, R8; J3; S2, S3.
- **Components**: `SimulatorScanner` (removal through `simctl delete`), the tool model and view, `AppState.confirm`.
- **Acceptance criteria**
  - [ ] The confirmation names the count, the size and the loss ("apps, data and snapshots"), and Cancel is the default.
  - [ ] The fake runner receives exactly `xcrun simctl delete <udid>`; if the tool fails, no folder is deleted.
  - [ ] A `Booted` device is not selectable ("Running · quit it first"); a device that becomes `Booted` between the scan and the action is refused with "“iPhone 15” is running: quit it first."
  - [ ] After the action the list is rescanned and the toast shows the space really freed; a partial failure shows "Devices that could not be removed: N".
  - [ ] A tool that does not answer in time shows "Xcode’s simulator service did not answer. Try again in a moment."
  - [ ] Manual: a disposable simulator (`xcrun simctl create`) is removed and is gone in Xcode; a booted simulator is refused.
- **Tests**: unit with a fake runner; manual on disposable targets.
- **Notes**: after this slice the first usable version for iOS exists (success criterion S2 is reachable with NuGet and the simulators).

### SL4: Darker supporting text across the app

- **Goal**: supporting text is readable in light mode everywhere, with almost the same grey.
- **Serves**: `DESIGN.md` accessibility decision (not R1 to R19).
- **Components**: the 69 uses of `.secondary` for text in 11 view files, `SectionHeader`, the two informative `.tertiary` texts (`CleanupToolViews.swift:87`, `NetworkTab.swift:106`).
- **Acceptance criteria**
  - [ ] Text that used `.secondary` uses text-supporting; icons keep `.secondary`.
  - [ ] `SectionHeader` is `.caption` in text-supporting; the two `.tertiary` texts use text-supporting; chevrons stay tertiary.
  - [ ] A test shows text-supporting at least 4.5 : 1 on both reference backgrounds (and 70 % with Increase Contrast).
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
  - [ ] With the variable set, the default path, or nothing, the locator behaves as specified (tests with an injected environment and home); without an SDK the Android group is hidden and iOS still works.
  - [ ] On a fake `~/.android/avd` in a temporary home: name, image, size and last-used date (from files) are read.
  - [ ] A running AVD is recognised from a recorded `ps` line containing `-avd <name>` and is not selectable.
  - [ ] Manual: the list matches Android Studio (6 AVD); with `ANDROID_SDK_ROOT` pointing to a missing folder, the Android group is hidden.
  - [ ] **Spike (risk 6):** one real running emulator is detected and refused; the result is written in `ARCHITECTURE.md`.
  - [ ] The best "last used" signal is chosen and written down (spec open question).
- **Tests**: unit, contract (`config.ini`, `ps`), manual.
- **Notes**: the Android group shows no removal yet.

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

- Could requirements: R14 (recommendations that point to the new cleaners), R15 (OrbStack, needs a tester).
- Simulator runtimes (31.5 GB outside the home folder): out of scope until the author decides; reopens ADR 0006 and 0009 together.
- Progressive sizes in the tool, if the first scan is slower than about 10 s.
- Whether the limit "Inactive for more than" is remembered between sessions.
- A local pre-commit hook for `swift test` (a habit today).
- Refactor of the four copies of the process helper onto the shared `CommandRunner`.

## Change log

| Date | Change | Reason |
| --- | --- | --- |
| 2026-11-15 | Plan created from the spec, architecture, design and test strategy. SL4 and SL5 placed after SL9 and kept out of the 14-day count | Author's decision during the slice step: protect the time box; SL3 stays before the tool because the screen depends on it |
| 2026-11-16 | SL7 started before the author's check of the classification on 5 devices. The check moves to before SL8 shows a default limit, and before the release at the latest | The limit is a parameter of the suggestion function, so SL7 does not depend on the check (author's instruction) |
