# 0008. Release built by GitHub Actions on Xcode 26

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | 2026-11-15 (made in a working session; the first runs on `macos-15` produced a defective 1.0.0) |
| Drives from | automatic, reproducible releases independent of the author's Mac |

## Context

The release (signed, notarized DMG and appcast) was first built by hand. It moved to GitHub Actions. The first run used `macos-15` (Xcode 16, SDK 15.5): the 1.0.0 DMG had no Liquid Glass (`#if compiler(>=6.2)`) and no translations (SwiftPM with Xcode 26 copies `.xcstrings` instead of compiling them). Evidence: `.github/workflows/release.yml`, `scripts/build-app.sh`, `CHANGELOG.md` 1.0.1, `docs/ci-release.md`.

## Options considered

### Option A: build by hand on the author's Mac (previous way)
- For: nothing to configure. Against: depends on one machine; easy to forget steps.

### Option B: GitHub Actions on `macos-15`
- For: default image. Against: Xcode 16 breaks Liquid Glass and translations (observed).

### Option C: GitHub Actions on `macos-26` with `xcstringstool` (chosen)
- For: SDK 26.5 (Liquid Glass); translations compiled by Apple's tool, identical to the local result.
- Against: tied to the runner's Xcode; guards needed.

## Decision

Option C. A tag `vX.Y.Z` runs `release.yml` on `macos-26`. Guards fail the job if Swift is older than 6.2 or no translation is produced. The Developer ID certificate lives in a temporary keychain; secrets are GitHub Actions secrets; a manual run is a dry run that publishes nothing.

## Consequences

- Good: one command (a tag) publishes; the dry run caught both defects before 1.0.1.
- Bad: depends on GitHub runner images; a new default Xcode could change the build.
- Risks: a secret expires or is revoked (notarization fails with a clear error); documented in `docs/ci-release.md`.

## Revisit when

The runner image changes its default Xcode, or Xcode 27 becomes available on runners (SwiftPM may then compile the catalogs itself).

## Open points

- Release 1.0.0 (defective) is still published.
