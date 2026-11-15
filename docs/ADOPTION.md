# Soaro: adoption report

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Date | 2026-11-15 |
| Level | standard |
| Mode | interview (4 questions) |
| Project state | released (1.0.1), maintenance, next feature chosen |

## Inventory

| Area | What was found | Source |
| --- | --- | --- |
| Stack | Swift 6 tools, Swift 5 language mode, SwiftUI plus AppKit, macOS 14+, Apple silicon. One dependency: Sparkle 2.10.1 | `Package.swift`, `Package.resolved` |
| Structure | One executable target `Soaro` (about 7 800 lines) and one test target (about 1 560 lines). `scripts/`, `site/`, `docs/`, `.github/` | file tree |
| Commands | `swift build`, `swift test` (verified), `scripts/build-app.sh` (verified), `scripts/release.sh`, `scripts/release-notes.sh`, CLI modes `--diagnostics --scan --advice --snapshot`. No lint or format tool | scripts, `docs/architecture.md` |
| Tests | Swift Testing, 135 tests in 30 suites, all passing (verified). No skipped test, no TODO or FIXME in sources, tests or scripts | `swift test`, grep |
| CI and release | `ci.yml` (build and test on `macos-26`), `release.yml` (tag or manual dry run: sign, notarize, DMG, GitHub release and appcast). Two releases: v1.0.0, v1.0.1 | `.github/workflows/` |
| Dependencies | Sparkle (maintained), system frameworks. No lockfile problem | `Package.resolved` |
| History | 15 commits between 2026-11-14 and 2026-11-15. Looks squashed or rewritten (first commit is an "Initial commit"). Single contributor. Pull requests and squash merges on GitHub | `git log` |
| Existing documentation | README (EN, FR), CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, CHANGELOG, `docs/` (architecture, updates, releasing, ci-release, website), website in `site/` | files |

## Documents produced

| Document | Confidence | Verified | Inferred | Open |
| --- | --- | --- | --- | --- |
| `CLAUDE.md` | high | commands run or read in scripts; conventions from git | branch and commit conventions (medium) | lint and format tools: none found |
| `STATUS.md` | high | state of releases, tests, site | success definition (donations) taken from one answer | no kill criterion; fate of release 1.0.0 |
| `ARCHITECTURE.md` | medium to high | components, flows, storage, cadence | cross-cutting "errors" and "cost" (medium); AppKit window reason (low) | reasons for Swift 5 mode and AppKit window |
| ADRs 0001-0008 | medium | the decisions as the code shows them | rationale and rejected options (mostly "not documented") | dates, alternatives, App Store evaluation |
| `TESTING.md` | high | suites, counts, CI gates | levels left out, fixtures (medium) | performance budget, accessibility |
| `SPEC.md`, `PLAN.md` | not produced (level `standard`) | | | next: `/trellis:incubate` for the developer-cache feature |

## Open questions

Things the code cannot tell, to confirm with the author.

1. Was Intel excluded on purpose or by build setup (ADR 0001)? Were the Mac App Store and a cross-platform shell evaluated (ADR 0001, 0002)?
2. Why is the package built in Swift 5 language mode, and is a move to Swift 6 wanted (author listed it as a fragile area)?
3. Why an AppKit window instead of a SwiftUI `Window` scene (inferred: idle cost, low confidence)?
4. Real date of each decision (the history is squashed to two days).
5. Success: "donations cover the Apple developer account". What number and by when, and what makes you stop (kill criterion)?
6. Release 1.0.0 is published and defective: keep, mark pre-release, or delete?
7. Is a performance budget check (idle RAM and CPU) wanted in CI?
8. The ADR-less rule: should Docker and OrbStack cleaning follow ADR 0006 (confirm, home folder) or need a new model (running containers, shared volumes)?
9. The conventions (French commit subjects, squash merge, signed commits) were inferred from history. Correct?

## Findings

- **Technical debt and fragile areas** (author's list plus inventory): private HID and SMC interfaces (ADR 0005); `AppState.swift` at 773 lines; Swift 5 language mode; `assets/icon.svg` still labelled "Accalmie".
- **Risks**: release and update chain depends on the `macos-26` runner, GitHub's redirect and the Cloudflare redirect rule (ADR 0003, 0008); the Sparkle private key has no second backup in the repository by design, only the author's copy and the GitHub secret; Sparkle window behaviour for a Dock-less app is unverified.
- **Missing tests**: `Updater` (Sparkle), `AppState` cadence logic, SwiftUI views and look, release scripts, opt-in defaults of the two network features, translation content.
- **Hotspots (most-changed files)**: `README.md` (6 commits), `scripts/build-app.sh` (4), `docs/releasing.md`, several views (3 each). Only 15 commits, so weak signal.
- **Hygiene**: no secrets-like file found in the repository. Secrets live in GitHub Actions secrets. The author's Apple certificate and Sparkle key export files were meant to be deleted after setup (not checked here).

## Suggested next steps

1. Review and confirm the reconstructed documents (edit them and remove the "reconstructed" mark item by item).
2. Decide the fate of release 1.0.0 (open question 6).
3. Specify the developer-cache feature with `/trellis:incubate`, starting with a spike on Docker and OrbStack safety (risk 2), then `/trellis:slice`.
4. Optional reviews: `security-reviewer` (the app deletes files and is not sandboxed), then `test-strategy` for the gaps listed above.

## Confirmation log

| Date | Item confirmed or corrected | By |
| --- | --- | --- |
| 2026-11-15 | Next step: extended developer caches | author |
| 2026-11-15 | Fragile areas: HID/SMC, `AppState` size, Swift 5 mode | author |
| 2026-11-15 | SQLite chosen for lightness and control (ADR 0004) | author |
| 2026-11-15 | Success: donations (to detail) | author |
