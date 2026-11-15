# Soaro: working notes for Claude

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

Soaro is a small, native macOS menu bar app (Swift, Apple silicon, macOS 14+) that watches CPU, GPU, memory, disk, network and battery, keeps a 30-day history, and suggests safe cleanups. Open source (GPL-3.0), no data leaves the Mac by default. Repository: `github.com/sebmafate/soaro`. Site: `soaro.app`.

## Documents

| File | What it is | Rule |
| --- | --- | --- |
| `SPEC.md` | What and why | Not written yet (adoption level `standard`); create it with `/trellis:incubate` when the next feature is specified |
| `ARCHITECTURE.md` | How: components, flows, decisions index | Update when reality changes |
| `docs/architecture.md` | File-by-file reference, CLI modes, macOS permissions, previous names | Detailed reference; `ARCHITECTURE.md` is the design view |
| `docs/adr/` | One decision per file | Never edit an accepted ADR; supersede it |
| `TESTING.md` | Test levels, baseline, definition of done | Follow it for every change |
| `PLAN.md` | Slices | Not written yet |
| `STATUS.md` | Current phase, next action | Keep current after each change |
| `CHANGELOG.md` | User-facing changes (Keep a Changelog) | One entry per release; the release notes are read from it |
| `docs/releasing.md`, `docs/ci-release.md`, `docs/updates.md`, `docs/website.md` | Release (manual and GitHub Actions), Sparkle, website | Source of truth for release steps |

## Commands

Verified on 2026-11-15 unless marked.

```sh
swift build                          # debug build
swift test                           # 135 tests in 30 suites, about 1 minute
scripts/build-app.sh                 # builds build/Soaro.app (ad hoc signature); --install copies to /Applications
SOARO_DEMO=1 build/Soaro.app/Contents/MacOS/Soaro    # run on made-up data (no measurement, nothing written)
.build/debug/Soaro --diagnostics     # print all measurements (read-only)
.build/debug/Soaro --scan            # run the cleanup scanners (read-only)
scripts/release.sh [--notarize]      # signed DMG + appcast (needs the Developer ID; normally run by CI)
scripts/release-notes.sh 1.0.1       # prints the CHANGELOG section of a version
# lint / format: none configured (unverified: no SwiftLint or swift-format file in the repository)
```

Releases are built by GitHub Actions on a `macos-26` runner when a tag `vX.Y.Z` is pushed (see `docs/ci-release.md`). **Do not build a release on an older Xcode**: Liquid Glass and translations need Swift 6.2+ and `xcstringstool`.

## Conventions

- Stack: Swift 6 tools, Swift 5 language mode, SwiftUI plus AppKit, one dependency (Sparkle). See ADR 0001.
- Branches and commits (observed in git history, confidence medium): short feature branches merged by pull request with a squash; commit subjects in French, in the imperative ("Ajouter...", "Renommer..."); commits are signed (SSH key). `main` is protected by a ruleset (pull request required, signed commits, no force push).
- Documentation and the user interface are in English first; French is the second language (README.fr.md, site `/fr/`). Code comments are mostly French.
- Version: `VERSION` file; the build number is the commit count (`git rev-list --count HEAD`), so a release build needs the full git history.
- Safety rule for anything that deletes: see ADR 0006. A path must pass `CleanupService.isSafeToDelete`, and the action is confirmed by the user first.
- Tests come first; a change is done only when its acceptance criteria are verified and the documents are updated (see `TESTING.md`).
- No personal data or secrets in the repository. Never print or commit the Sparkle private key or certificates.

## Working here with Trellis

- Continue the project: `/trellis:resume`, then `/trellis:deliver`.
- A requirement, decision or design changes: `/trellis:change-course`.
- A choice worth recording: `/trellis:adr`. An unknown to settle: `/trellis:spike`.
- This project was adopted from existing code: documents marked "reconstructed" are hypotheses until confirmed.
