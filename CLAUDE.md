# Soaro: working notes for Claude

> Reconstructed on 2026-11-15 from the code and history. Facts re-checked on 2026-11-17 (commands run, test count measured, plan and status brought to the merged state of `main`, slices SL1 to SL12a). The branch and commit conventions below are still inferred from history and not yet confirmed by the author.

Soaro is a small, native macOS menu bar app (Swift, Apple silicon, macOS 14+) that watches CPU, GPU, memory, disk, network and battery, keeps a 30-day history, and suggests safe cleanups. Open source (GPL-3.0), no data leaves the Mac by default. Repository: `github.com/sebmafate/soaro`. Site: `soaro.app`.

## Documents

| File | What it is | Rule |
| --- | --- | --- |
| `SPEC.md` | What and why | Covers the developer cleanup feature only (written 2026-11-15); requirement IDs R1 to R19 are stable, do not renumber |
| `ARCHITECTURE.md` | How: components, flows, decisions index | Update when reality changes |
| `DESIGN.md` | UX and UI of the developer cleanup (journeys J1 to J6, screens S1 to S4) | Parts 1 (UX) and 2 (UI) written 2026-11-15 |
| `docs/architecture.md` | File-by-file reference, CLI modes, macOS permissions, previous names | Detailed reference; `ARCHITECTURE.md` is the design view |
| `docs/adr/` | One decision per file | Never edit an accepted ADR; supersede it |
| `TESTING.md` | Test levels, baseline, definition of done | Follow it for every change |
| `PLAN.md` | Slices (SL1 to SL14, SP1) of the developer cleanup, in execution order; days spent against the 14-day time box | Written 2026-11-15. SL1 to SL12a are done and merged (2026-11-16 and 2026-11-17); SL12b is blocked on the author; SP1, SL13 and SL14 remain |
| `STATUS.md` | Current phase, next action | Keep current after each change |
| `CHANGELOG.md` | User-facing changes (Keep a Changelog) | One entry per release; the release notes are read from it |
| `docs/releasing.md`, `docs/ci-release.md`, `docs/updates.md`, `docs/website.md` | Release (manual and GitHub Actions), Sparkle, website | Source of truth for release steps |

## Commands

Verified on 2026-11-17 in a fresh worktree of `main` unless marked.

```sh
swift build                          # debug build
swift test                           # 1035 tests in 91 suites; about 40 s from a clean build, about 3 s when already built
scripts/build-app.sh                 # builds build/Soaro.app (ad hoc signature); --install copies to /Applications
SOARO_DEMO=1 build/Soaro.app/Contents/MacOS/Soaro    # run on made-up data (no measurement, nothing written)
DYLD_FRAMEWORK_PATH=.build/debug .build/debug/Soaro --diagnostics   # print all measurements (read-only)
DYLD_FRAMEWORK_PATH=.build/debug .build/debug/Soaro --scan          # run the cleanup scanners (read-only)
scripts/release.sh [--notarize]      # signed DMG + appcast (needs the Developer ID; normally run by CI)
scripts/release-notes.sh 1.0.1       # prints the CHANGELOG section of a version
# lint / format: none configured (unverified: no SwiftLint or swift-format file in the repository)
```

Notes on the commands:

- The debug binary does not know where Sparkle is: started alone it stops with `Library not loaded: @rpath/Sparkle.framework/...`. `DYLD_FRAMEWORK_PATH=.build/debug` fixes it (`.build/debug` is a link to `.build/out/Products/Debug`, where `Sparkle.framework` sits). In a FRESH worktree `.build/debug` may not hold `Sparkle.framework` yet (the link target is missing until a build has produced it); the alternative is `DYLD_FRAMEWORK_PATH=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64` (the downloaded binary, checked with `ls` on 2026-11-17). `build/Soaro.app` needs nothing: `scripts/build-app.sh` puts the framework in `Contents/Frameworks` and adds the matching run path.
- A first `swift build` downloads the Sparkle binary. If it hangs (it did, for about 10 minutes, during SL1), copy an existing `.build/artifacts` folder into the new checkout's `.build/` and run it again.
- Checked on 2026-11-17: `swift build`, `swift test`, `scripts/build-app.sh` (builds, ad hoc signature), `--diagnostics`, `--scan` (with the variable above) and `scripts/release-notes.sh`. Not run that day: `SOARO_DEMO=1 build/Soaro.app/Contents/MacOS/Soaro` (it opens the app), `--install` and `scripts/release.sh` (needs the Developer ID).

Releases are built by GitHub Actions on a `macos-26` runner when a tag `vX.Y.Z` is pushed (see `docs/ci-release.md`). **Do not build a release on an older Xcode**: Liquid Glass and translations need Swift 6.2+ and `xcstringstool`.

## Conventions

- Stack: Swift 6 tools, Swift 5 language mode, SwiftUI plus AppKit, one dependency (Sparkle). See ADR 0001.
- Branches and commits (observed in git history, confidence medium): short feature branches merged by pull request (merge commit for pull request #1, squash for #2 to #5, merge commit from #6 on); commit subjects in French, in the imperative ("Ajouter...", "Renommer..."); commits are signed (SSH key). `main` is protected by a ruleset (pull request required, signed commits, no force push).
- Documentation and the user interface are in English first; French is the second language (README.fr.md, site `/fr/`). Code comments are mostly French.
- Version: `VERSION` file; the build number is the commit count (`git rev-list --count HEAD`), so a release build needs the full git history.
- Safety rule for anything that deletes: see ADR 0006. A path must pass `CleanupService.isSafeToDelete`, and the action is confirmed by the user first.
- Tests come first; a change is done only when its acceptance criteria are verified and the documents are updated (see `TESTING.md`).
- No personal data or secrets in the repository. Never print or commit the Sparkle private key or certificates.

## Lessons learned

- **The CI compiler is older than the local one and can reject code that compiles locally.** The CI runner (`macos-26`; Xcode 26.6 per `TESTING.md`, not re-checked: `ci.yml` does not pin Xcode) has an older toolchain than the author's Mac (Swift 6.4, Xcode 27), so it may reject code the local compiler accepts. In SL12a, a local constant named like the function called in its own initializer (`let key = try #require(key(...))`, the same pattern with `version`) compiled locally and failed on CI (fixed by renaming the constants in commit `b5d4aa3`). The CI failure only shows after the push: name a local differently from any function you call in the same statement.
- **Demo mode (`SOARO_DEMO=1`) must stay inert.** No destructive path may run in demo: no delete, trash, `launchctl`, quitting a real app or removal through a tool, from any row, tool, switch or button. Until the SL6 review round it did run some of them. Every new model has a demo-mode branch: nothing measured or written in demo mode (see the definition of done in `TESTING.md`).

## Working here with Trellis

- Continue the project: `/trellis:resume`, then `/trellis:deliver`.
- A requirement, decision or design changes: `/trellis:change-course`.
- A choice worth recording: `/trellis:adr`. An unknown to settle: `/trellis:spike`.
- This project was adopted from existing code: documents marked "reconstructed" are hypotheses until confirmed. The developer cleanup documents (`SPEC.md`, `ARCHITECTURE.md`, `DESIGN.md`, `TESTING.md`, `PLAN.md`) were written on 2026-11-15 and have been followed by delivery since (SL1 to SL12a).
