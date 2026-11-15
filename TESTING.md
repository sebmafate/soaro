# Soaro: test strategy (baseline)

> Reconstructed on 2026-11-15 from the code and history. To be confirmed. This file records the **current state**; it does not invent a strategy.

| | |
| --- | --- |
| Status | draft (reconstructed baseline) |
| Version | 0.1 |
| Date | 2026-11-15 |
| Based on | the code at `e4520dd`; no `SPEC.md`, so the matrix is by feature area |

## Goals and risks

Goal: change the code with confidence, without a real Mac in the loop for most checks.

| # | What would hurt most if wrong | Why it is risky | Where it is tested |
| --- | --- | --- | --- |
| T1 | Deleting something outside the cleanup scope, or without consent | Destroys user data and trust | `CleanupSafetyTests`, `DevArtifactScannerTests`, `AppUninstallerTests`, `LargeFileScannerTests`, `CleanupKindTests` (automated) |
| T2 | Wrong measurement shown as real (sensors, battery, network) | Misleads the user | Parsing and decoding tests: `BatteryParsingTests`, `NetworkParsingTests`, `EnergyParsingTests`, `SMCDecodingTests`, `ProcessParsingTests`, `SamplerTests`. Not on real hardware |
| T3 | Wrong recommendation or false alarm | Annoys or misleads | `RecommendationEngineTests`, `NewRecommendationTests`, `LeakDetectorTests`, `Advice*Tests`, threshold tests |
| T4 | Broken update or release (bad signature, missing translations, bad build number) | Users stranded or app defective | CI dry run (`release.yml` by hand) and the release guards. **Not covered by unit tests** |
| T5 | Lost history or preferences after a rename or upgrade | Data loss | `HistoryStoreTests`, `LegacyMigrationTests` |
| T6 | A network call that should be off or opt-in | Breaks the privacy promise | `PublicIPParsingTests`, `InternetIdentityTests` (parsing and validation). Opt-in default itself: no test (unverified) |

Hard to test: private HID and SMC interfaces (real hardware), Sparkle in a running app, the menu bar panel behaviour, Liquid Glass appearance, notarization.

## Test levels

| Level | Covers | Tool | Runs where | When |
| --- | --- | --- | --- | --- |
| Unit | Pure functions, parsers, formatting, scanners on temporary folders, in-memory SQLite | Swift Testing (`@Suite`, `@Test`), 135 tests in 30 suites | local, CI (`macos-26`) | every push to `main` and every pull request |
| Integration | None as a separate level | n/a | n/a | n/a |
| End to end | None automated. `--snapshot`, `--diagnostics`, `--scan`, demo mode (`SOARO_DEMO=1`) support manual runs | `scripts/make-screenshots.sh`, CLI modes | local | on demand |
| Accessibility | None | n/a | n/a | n/a |
| Manual and exploratory | Install of the DMG on a clean user, Gatekeeper check, update from the previous version | `docs/releasing.md`, `docs/ci-release.md` | local | each release |

Levels left out, and why: not documented; inferred from project size (one maintainer).

## Verification matrix (by feature area)

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
| Translations (nine languages) | secondary | none | release guard fails if no translation compiles; content is not checked | partly (build guard) |
| Update (Sparkle) | core | Manual | update 1.0.0 to 1.0.1 inside the app | no |
| Release chain (sign, notarize, DMG, appcast) | core | Dry run | `workflow_dispatch` on `release.yml`; `spctl`, `stapler validate` by hand | partly |
| SwiftUI views and look | secondary | none | `--snapshot` screenshots by eye | no |

Success criteria measured only after release: none defined (no `SPEC.md`).

## Test data and environments

- Fixtures: sample output strings of `nettop`, `top`, `ps`, IOKit dictionaries, SMC byte arrays, in the test files. **[M]**
- Real versus synthetic: scanners use temporary folders; the history uses `:memory:`. **[H]**
- Doubles for external services: parsing of recorded replies, no live call. **[M]**
- Time, randomness, concurrency: tests pass explicit `now` and locale (`HistoryStore.query(range:now:)`, `Format` takes a `locale`). **[H]**
- Environments: local Mac (macOS 27, Xcode 27) and the `macos-26` runner (Xcode 26.6). Not tested on macOS 14 or 15. **[H]**

## Quality gates

| Moment | What runs | Blocks | Warns |
| --- | --- | --- | --- |
| Each commit | nothing automatic (no hook found) | | |
| Each pull request | `swift build` and `swift test` (`ci.yml`) | failing tests | none |
| Each release | `release.yml`: version and tag match, CHANGELOG section present, Swift version at least 6.2, `swift test`, build, translation guard, notarization | any failure | none |

Flaky test policy: none written; no flaky test known.

## Non-functional and manual testing

- Performance budgets: 20-35 MB RAM and 1-2% of a core when idle (README). **No test or measurement script in the repository.**
- Security and privacy checks: none automated. `SECURITY.md` describes reporting.
- Accessibility checks: none.
- Manual checklist (release): open the DMG on a clean account, `spctl -a -t open --context context:primary-signature -vv`, launch with no Gatekeeper warning, update from the previous version (`docs/ci-release.md`).

## Definition of done (per change)

- [ ] Tests written first or alongside, and passing (`swift test`)
- [ ] Acceptance criteria verified
- [ ] Relevant rows of the verification matrix updated
- [ ] Documentation, `CHANGELOG.md` and `STATUS.md` updated
- [ ] No new warnings

## Tooling decisions

| Decision | ADR or note |
| --- | --- |
| Swift Testing rather than XCTest | no ADR; observed in all test files |
| CI on `macos-26` | ADR 0008 |

## Testability findings for the architecture

- `AppState` (773 lines) mixes timing, sampling and actions and has no test of its own; extracting the cadence rules would make them testable.
- The views have no automated check; `--snapshot` helps a human, not CI.
- Sensors and network samplers call system tools and IOKit directly; only their parsers are tested.

## Open points

- Is a performance budget check wanted (idle RAM and CPU)?
- Strict concurrency (Swift 6 mode) as a gate: not enabled.
- No test of the opt-in default of the two network features (T6).
