# Soaro: test strategy

> The baseline parts (existing features) were reconstructed on 2026-11-15 from the code and history, to be confirmed. The developer cleanup parts were designed on 2026-11-15 from `SPEC.md` v0.3.

| | |
| --- | --- |
| Status | draft |
| Version | 0.2 |
| Date | 2026-11-15 |
| Based on | the code at `e4520dd` (135 tests, 30 suites, about 5 s when built; 172 tests after SL1 and SL2; 262 tests in 42 suites with SL7), `SPEC.md` v0.3, `ARCHITECTURE.md` v0.2 (ADR 0009, 0010), `DESIGN.md` v0.1 |

## Goals and risks

Goals: fast feedback while coding (the suite stays in the order of tens of seconds); confidence before a release **without ever running a destructive action against a real tool**; a short manual checklist on the author's Mac for the success criteria.

| # | What would hurt most if wrong | Why it is risky | Where it is tested |
| --- | --- | --- | --- |
| T1 | Deleting something outside the cleanup scope, or without consent | Destroys user data and trust | `CleanupSafetyTests`, `DevArtifactScannerTests`, `AppUninstallerTests`, `LargeFileScannerTests`, `CleanupKindTests` (automated) |
| T2 | Wrong measurement shown as real (sensors, battery, network) | Misleads the user | Parsing and decoding tests: `BatteryParsingTests`, `NetworkParsingTests`, `EnergyParsingTests`, `SMCDecodingTests`, `ProcessParsingTests`, `SamplerTests`. Not on real hardware |
| T3 | Wrong recommendation or false alarm | Annoys or misleads | `RecommendationEngineTests`, `NewRecommendationTests`, `LeakDetectorTests`, `Advice*Tests`, threshold tests |
| T4 | Broken update or release (bad signature, missing translations, bad build number) | Users stranded or app defective | CI dry run (`release.yml` by hand) and the release guards. **Not covered by unit tests** |
| T5 | Lost history or preferences after a rename or upgrade | Data loss | `HistoryStoreTests`, `LegacyMigrationTests` |
| T6 | A network call that should be off or opt-in | Breaks the privacy promise | `PublicIPParsingTests`, `InternetIdentityTests` (parsing and validation); the network allowlist test (T11) closes the gap for new code. Opt-in default: `OptInDefaultsTests` checks `SettingsKey.defaults` (`publicIP` and `latency` are `false`, `notifications` is `true` for contrast). **Limit:** the `@AppStorage(...) = false` defaults written in `NetworkTab` and `SettingsView` are not readable from a test, so they are not covered |
| **T7** | Removing the wrong simulator or emulator, or a running one (R4, R5, R17, S3) | Data loss; kill criterion 2 of the spec | Unit tests with a fake command runner, never the real tool; one manual removal of a disposable device |
| **T8** | A missing, slow, failing or changed tool breaks the view or the app (R6, A5) | Xcode, Android and Docker change their outputs; a command can hang | Unit tests: absent, failing, timed out, malformed output; contract tests on recorded real outputs |
| **T9** | A wrong suggestion (R3, R16) or a wrong size or "freed" amount (R7) | Misleads the user; `Docker.raw` is 995 GB apparent and 24 GB real | Pure function tested at a fixed date; allocated size tested on a sparse file |
| **T10** | Confirmations: Return deletes today, and the accessibility slice changes shared components (R8) | Regression on screens already published | Test of the alert construction; the existing tool tests |
| **T11** | A network call, or an incomplete translation (R9, R12) | Privacy promise; missing texts in eight languages | Two repository-level tests: `NetworkAllowlistTests`, `TranslationCatalogTests` (both read the repository through `#filePath`, no network) |
| **T12** | Docker gives no space back to the Mac (R11) | The Docker feature has no value | Test B, manual, once |

Hard to test: private HID and SMC interfaces (real hardware), the real `simctl`, Android tools and `docker`, a really running emulator, Sparkle in a running app, the menu bar panel behaviour, VoiceOver, Liquid Glass and contrast on glass, notarization.

## Test levels

| Level | Covers | Tool | Runs where | When |
| --- | --- | --- | --- | --- |
| Unit | Pure functions, parsers, formatting, scanners on temporary folders, in-memory SQLite. New: the suggestion function, the parsers of recorded tool outputs, scanners with a **fake command runner** | Swift Testing (`@Suite`, `@Test`) | local, CI (`macos-26`) | every pull request |
| Integration (new, small) | The real `CommandRunner` against harmless programs (`/bin/echo`, `/bin/sleep`, `/usr/bin/yes`): time limit kills the process, output is bounded, a relative path or a shell is refused | Swift Testing | local, CI | every pull request |
| Contract (new) | Real outputs from the author's Mac (`simctl list devices -j`, AVD `config.ini`, `ps` lines, `docker system df`), anonymised and written inline: a format change in a tool breaks a test | Swift Testing | local, CI | every pull request |
| End to end | None automated. `SOARO_DEMO=1`, `--scan` (read-only) and `--snapshot` support manual runs | `scripts/make-screenshots.sh`, CLI modes | local | on demand |
| Accessibility | Automated: a test computes the contrast ratios of the colors defined in `DESIGN.md`. Manual: VoiceOver, keyboard, Reduce Motion, Increase Contrast, Reduce Transparency | Swift Testing, checklist below | local | each release |
| Security and privacy | Network allowlist; the runner refuses relative paths and shells; an AVD path outside the home folder is refused | Swift Testing | local, CI | every pull request |
| Manual and exploratory | Install of the DMG on a clean user, Gatekeeper, update from the previous version; the developer cleanup checklist below | `docs/releasing.md`, `docs/ci-release.md`, this file | local | each release |

Levels left out, and why: property-based (no function whose input space needs it); image snapshots (Liquid Glass is not drawn off screen, so a pixel comparison would be meaningless); automated performance tests (no measurement tool in the repository, so performance stays a manual check).

## Verification matrix

### Existing features (by area, reconstructed)

| Area | Priority | Level | Concrete check | Automated |
| --- | --- | --- | --- | --- |
| CPU, memory, disk, processes | core | Unit | `SamplerTests`, `ProcessParsingTests` | yes |
| GPU, battery, disk I/O | core | Unit (parsers) | `BatteryParsingTests`, `EnergyParsingTests` | yes (no hardware) |
| Sensors (temperature, fans, power) | core | Unit (decoding) | `SMCDecodingTests` | yes (no hardware) |
| Network, VPN, public IP, flags | core | Unit (parsers) | `NetworkParsingTests`, `VPNDetectorTests`, `PublicIPParsingTests`, `FlagTests` | yes |
| History | core | Unit | `HistoryStoreTests` | yes |
| Recommendations and tips | core | Unit | `RecommendationEngineTests`, `NewRecommendationTests`, `LeakDetectorTests`, `Advice*Tests` | yes |
| Cleanup: caches, large files, dev folders | core | Unit | `CleanupToolsTests`, `CleanupSafetyTests` | yes |
| App uninstaller, login items | core | Unit | `AppUninstallerTests`, `StartupItemsTests` | yes |
| Menu bar label, thresholds, tooltips | core | Unit | `MenuBarItemTests`, `PressureLevelTests`, `AdjustableThresholdTests`, `MenuBarTooltipTests` | yes |
| Window and panel visibility | secondary | Unit | `VisibilityTests` | yes |
| Formatting and locales | secondary | Unit | `RateFormatTests`, `MachineInfoTests` | yes |
| Migration from old names | secondary | Unit | `LegacyMigrationTests` | yes |
| Translations (nine languages) | secondary | Build guard, plus the catalog test (R12) | the release guard fails if no translation compiles; `TranslationCatalogTests` checks the content of `Localizable.xcstrings` and `InfoPlist.xcstrings` | yes |
| Update (Sparkle) | core | Manual | update 1.0.0 to 1.0.1 inside the app | no |
| Release chain (sign, notarize, DMG, appcast) | core | Dry run | `workflow_dispatch` on `release.yml`; `spctl`, `stapler validate` by hand | partly |
| SwiftUI views and look | secondary | Manual | `--snapshot` screenshots by eye | no |

### Developer cleanup (`SPEC.md`, R1 to R19)

| ID | Priority | Level | Concrete check | Automated |
| --- | --- | --- | --- | --- |
| R1 | Must | Unit, manual | NuGet folder path, listed items and size on a fake tree; the row is hidden if the folder does not exist. Manual: the real cleanup frees about the 13 GB (within 10 %) | yes, then manual |
| R2 | Covered | Unit | the "App caches" cleaner includes `org.swift.swiftpm` and never `~/Library/org.swift.swiftpm` | yes |
| R3 | Must | Unit, manual | Table-driven cases from test A: inactive beyond the limit, older copies of the same model and runtime, devices under 100 MB not listed, a variable limit. Manual: the author's check on 5 devices | yes (SL7: `DeviceSuggestionsTests`, fixed `now`, limit always passed explicitly, 59/60/61 days at 60, limits 30/90/180, duplicates, small devices at 99,999,999 and 100,000,000 bytes). **Manual, still open:** the author's check on 5 devices, which confirms or changes the provisional 60-day default |
| R4 | Must | Unit, manual | The fake runner receives exactly `xcrun simctl delete <udid>`; when the tool fails, **no folder is deleted** (no fallback). Manual: one disposable real device | yes, then manual |
| R5 | Must | Unit | A `Booted` device is never pre-selected nor removed, even if it becomes `Booted` between the scan and the action | partly (SL7: a device whose state is not `Shutdown` is never pre-selected, whatever its age, and counts as the newest copy of its group; `DeviceSuggestionsTests`). **Not yet:** the removal and the re-check between scan and action (SL9) |
| R6 | Must | Unit | Tool absent, non-zero exit, time limit exceeded, malformed JSON: the entry hides, the other platform stays usable, no error reaches the user | yes for iOS in `--scan` (SL7: `SimulatorScannerTests` with the fake runner: tool not found, non-zero exit, timed out, malformed or truncated output, empty list; `SimulatorParsingTests` on the anonymised recorded output; `SimulatorReportTests`: one neutral line per failure). **Not yet:** the entry hiding in the screen (SL8) and Android (SL10) |
| R7 | Must | Unit, manual | Size uses the allocated space (a 1 GB sparse file weighs little); the freed amount equals before minus after. Manual: compare with `df` and `du`, within 10 % | sizes yes (SL7: a 1 GB sparse file on `CleanupService.allocatedSize` and in the scanner; manual check of 2026-11-16: allocated total 1.02 times `du -sk` of the devices folder). **Not yet:** the freed amount, before minus after (SL9) |
| R8 | Must | Unit | Cancel is the default button for the five confirmations; the text holds the count, the size and what is lost; cancelling deletes nothing (needs the injectable confirmation) | yes (SL1: alert construction and cancelled confirmation of the four models; Escape by hand) |
| R9 | Must | Security | Only `PublicIPService.swift` references `URLSession` or `NWConnection`; the runner refuses a relative path and a shell | yes (SL7: `CommandRunnerIntegrationTests` on `/bin/echo`, `/bin/sleep`, `/usr/bin/yes`, `/usr/bin/false`: relative and empty paths, `sh`, `bash`, `zsh`, `dash`, `ksh`, `csh`, `tcsh`, `env`, `/bin/../bin/sh` and a symlink to a shell are refused and nothing is launched; `NetworkAllowlistTests`: raw substring match on every `.swift` under `Sources/Soaro/`, comments included, so a comment that names `URLSession` elsewhere fails on purpose). **Not covered:** Sparkle (`Updater.swift`), `NWPathMonitor`, `Data(contentsOf:)`, `Process`/`curl`, and the opt-in `/sbin/ping` run by `NetworkSampler.ping` |
| R10 | Should | Unit, manual | The commands issued belong to an allowlist (never volumes, containers or the reclaim container); manual: Test B | yes, then manual |
| R11 | Should | Manual, then unit | Test B; afterwards "returned = free after minus free before" with an injected free-space provider | partly |
| R12 | Should | Unit | Every key of the catalogs has the nine languages, and the placeholders (`%@`, `%lld`, `%d`, `%1$@`, `%%`) match between languages | yes (`TranslationCatalogTests`: `realLocalizableCatalogIsCompleteInEveryLanguage`, `realInfoPlistCatalogIsCompleteInEveryLanguage`, plus the pure checks on in-memory catalogs). Exclusions: exactly five keys of `Localizable.xcstrings` with an empty entry (`""`, `"%@ %@"`, `"%@ / %@"`, `"%@ · %@"`, `"%lld °C"`); an exclusion whose key disappears fails. A key without placeholder is never formatted at runtime, so `% zu` there is not a gap but `%%` is |
| R13 | Should | Unit | `includedInQuickClean` is false for NuGet; the quick clean total excludes it | yes |
| R14 | Could | Unit if built | recommendation engine | n/a |
| R15 | Could | Manual | Needs an OrbStack tester; not verified here | no |
| R16 | Must | Unit, manual | A fake `~/.android/avd` in a temporary home: name, image, size and date from the files; a running AVD detected from a recorded `ps` line (`-avd Pixel_9a`). Manual: compare with Android Studio (6 AVD) | yes, then manual |
| R17 | Must | Unit, manual | Removes the `.ini` and `.avd` pair only; a `path=` outside the home folder is refused; a neighbouring AVD stays; refused if running. Manual: create then remove a disposable AVD, compare with `avdmanager list avd` (risk 5) | yes, then manual |
| R18 | Must | Unit, manual | Locator with the variable set, the default path, and nothing. Manual: on the author's Mac, where the tools are not in the PATH | yes, then manual |
| R19 | Should | Unit, manual | Matching of image to AVD by `image.sysdir.1`; an image in use is never suggested. Manual: the author's 6 images | yes, then manual |

### Accessibility slice (before the tool, `DESIGN.md` Open points)

| Item | Level | Concrete check | Automated |
| --- | --- | --- | --- |
| Cancel is the default button (R8) | Unit | the alert is built separately from being shown; the default is Cancel for all five callers | yes |
| Colors keep their contrast | Unit | danger-fill with a white label at least 4.5 : 1; text-supporting at least 4.5 : 1 on both reference backgrounds | yes |
| Shared `SelectionRow` and `ActionBar` | Unit, manual | the existing tool tests still pass; manual VoiceOver reads the device name | partly |
| Toast: fade with Reduce Motion, VoiceOver announcement | Manual | turn Reduce Motion on and trigger a toast; with VoiceOver, the message is spoken | no |
| Supporting text color across the app | Manual | `--snapshot` screenshots of every tab compared with the previous ones: only the grey changes | no |

### Success criteria measured after release

| Criterion | How it is observed |
| --- | --- |
| S1: used monthly for 2 months | the author's own note in `STATUS.md` after 2 months (Soaro sends no data) |
| S2: at least 30 GB freed at the first pass | the total shown by Soaro at the first run, written in `STATUS.md` |
| S3: zero data lost by mistake | GitHub issues and the author's own use |

Kill criteria are watched in `PLAN.md` (days spent against the 14 working days) and in the Docker Test B result.

## Test data and environments

- **Fixtures:** real outputs from the author's Mac, **anonymised and written inline** in the test files: the home path becomes `/Users/test`, device identifiers are made up, and the author's project and bundle names become `com.example.app`. The full real outputs stay outside the repository. `Package.swift` does not change.
- **Doubles:** a hand-written `FakeCommandRunner` scripted by command (output, exit code, delay), no mocking library. Injected parameters: the root or home folder, `now`, the environment variables, the free-space provider, the process list and the confirmation.
- **Rule for destructive paths:** the scanners and removers take the command runner as a parameter **with no default value**, so a test cannot reach the real tool by accident. The real runner is built only where the app is assembled.
- **Temporary folders:** tests that delete create a unique folder in the home folder with the prefix `.soaro-test-`, as `Sandbox` does today, because `isSafeToDelete` only accepts the home folder. They never touch `~/.android`, `~/Library/Developer` or `~/.nuget`.
- **Time and concurrency:** explicit `now` and locale, as today. Scans run in detached tasks with a cancellation token: tests call the synchronous scanner function, not the task.
- **Environments:** the author's Mac (macOS 27, Xcode 27) and the `macos-26` runner (Xcode 26.6). The runner has Xcode simulators, so no test may depend on, or call, the real `simctl`. Not tested on macOS 14 or 15 (existing gap).
- **Repository-level tests (new):** the catalog test reads `Sources/Soaro/Resources/Localizable.xcstrings` as JSON through a path computed from `#filePath`; the network test reads the sources the same way.

## Quality gates

| Moment | What runs | Blocks | Warns |
| --- | --- | --- | --- |
| Each commit | nothing automatic (no hook found). Run `swift test` yourself | | |
| Each pull request | `swift build` and `swift test` (`ci.yml`), now including the network, catalog and contrast tests | failing tests | none |
| Each release | `release.yml`: version and tag match, CHANGELOG section present, Swift version at least 6.2, `swift test`, build, translation guard, notarization. Plus the manual checklists below | any failure | none |

Flaky tests: a flaky test is a defect. It is fixed or removed in the same slice; it is never made to pass by retrying. None is known today.

Regression in a measured quality: none is measured automatically. Performance is a manual check (below).

## Non-functional and manual testing

- **Performance budget (existing):** 20-35 MB RAM and 1-2 % of one core when idle (README). The new tools must add no work to the 3-second tick. Before the first release, sample the process for a minute with `ps -o %cpu,rss` and compare with the budget. Also note the time of the first scan on the author's Mac: above about 10 s, the list switches to progressive sizes (`DESIGN.md`).
- **Security and privacy:** the network allowlist test; the runner refuses shells and relative paths; the AVD path check; fixtures reviewed for personal data (home path, user name, project names) before each commit.
- **Accessibility checklist (each release):** VoiceOver reads each device row as one item with name, system, size, reason and state; Full Keyboard Access reaches every control and Space toggles a row; Reduce Motion gives a plain fade for the toast; Increase Contrast darkens the destructive button; Reduce Transparency and Increase Contrast on glass and material backgrounds; the controls measure at least 24 x 24 pt (Accessibility Inspector); the Text size settings: is Soaro listed?
- **Developer cleanup checklist, on the author's Mac, before the first release:**
  1. `--scan` (read-only) lists the simulators and the AVD; the list matches `xcrun simctl list` and Android Studio.
  2. Create a disposable simulator (`xcrun simctl create`) and a disposable AVD; remove them with Soaro; check they are gone in Xcode, Android Studio and `avdmanager list avd`; compare what is left on disk for the AVD (risk 5).
  3. Boot a simulator and start an AVD: Soaro refuses to remove them (risk 6).
  4. Launch the binary with `ANDROID_SDK_ROOT` pointing to a folder that does not exist: the Android group is hidden and iOS still works.
  5. Run the NuGet cleanup: about 13 GB freed, confirmed with `df`.
  6. Dark and light, panel and window, one CJK language and German for long strings.
  7. Docker Test B (ADR 0010), with the author starting Docker Desktop and confirming each prune.
- **Dogfooding exit:** the two-month period of success criteria S1 to S3.

## Definition of done (per slice)

- [ ] Tests written first or alongside, and passing (`swift test`; baseline of the current branch: 262 tests in 42 suites after SL7)
- [ ] Acceptance criteria verified; the rows of the matrix updated
- [ ] No test calls a real simulator, Android or Docker tool, and the destructive paths take their runner as a parameter without a default
- [ ] Fixtures anonymised (no home path, user name, project or bundle name)
- [ ] New user-facing strings translated in the nine languages, and the catalog test passes
- [ ] A change to a shared component: the existing tool tests pass and VoiceOver reads the new labels
- [ ] A destructive path was tried once on a disposable target before merging
- [ ] A demo-mode branch for every new model (nothing measured or written in demo mode)
- [ ] Documentation, `CHANGELOG.md`, `STATUS.md` and the days spent in `PLAN.md` updated
- [ ] No new warnings

SL7 (iOS simulators in `--scan`), done 2026-11-16: the items "a demo-mode branch for every new model", "new user-facing strings translated" and "a destructive path was tried once on a disposable target" are **not applicable to SL7** (no model, no screen, no new string in the catalog, nothing is removed). Fixtures are anonymised (the one real recording was made outside the repository and deleted).

## Tooling decisions

| Decision | ADR or note |
| --- | --- |
| Swift Testing rather than XCTest | no ADR; observed in all test files |
| CI on `macos-26` | ADR 0008 |
| Hand-written fake command runner, no mocking library | note (cheap to change) |
| Fixtures inline in the tests, no test resources | note (keeps `Package.swift` unchanged) |
| Catalog and network checks as ordinary unit tests reading the sources | note |
| No coverage target | note |

No decision here is hard to reverse, so no new ADR.

## Testability findings for the architecture

Already recorded in `ARCHITECTURE.md` (Testing, 2026-11-15):

1. The cleanup models called `AppState.confirm` directly (a static, modal call), so "cancelling deletes nothing" could not be tested. **Done by SL1 (2026-11-16):** the four models take an injectable confirmation with a default (`AppState.cleanup` does not, by design of SL1).
2. `CleanupService.directory(for:)` reads `NSHomeDirectory()` directly. The home folder must be a parameter with a default, so NuGet (R1) and "App caches" (R2) can be tested without the real home.
3. New scanners take the root, `now` and the command runner as parameters.

Still open from the baseline:

- `AppState` (773 lines) mixes timing, sampling and actions and has no test of its own.
- The views have no automated check; `--snapshot` helps a human, not CI.
- The samplers call system tools and IOKit directly; only their parsers are tested.
- The toast announcement for VoiceOver is in `AppState.showToast` and can only be checked by hand.

## Open points

- Is a performance budget check wanted (idle RAM and CPU)? Today: a manual sample before each release.
- Strict concurrency (Swift 6 mode) as a gate: not enabled.
- The opt-in default of the two network features (T6): closed by SL2 for the registered defaults (`SettingsKey.defaults`); the view-level `@AppStorage` defaults stay unreadable from a test. Open: `Text("...")` was not checked for the no-placeholder rule of the catalog test (only `String(localized:)`).
- A local `swift test` before each commit stays a habit, not a hook (a gate that is too strict gets bypassed).
- Not tested on macOS 14 or 15, the stated minimum.
- Test B (Docker) has no date; it needs the author to start Docker Desktop.
