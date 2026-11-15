# 0006. Confirmed, home-folder-only deletion; Trash when recoverable

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | unknown; before 1.0.0 |
| Drives from | decision driver 1: never lose user data |

## Context

A cleaning tool that deletes the wrong thing destroys trust. Soaro scans caches, large files, dev project folders and app leftovers. Evidence: README "Safety", `CleanupService.isSafeToDelete`, `AppUninstaller.swift` (`trashItem`), `DevArtifactScanner.swift`, `CleanupSafetyTests`, `DevArtifactScannerTests`, `AppUninstallerTests`.

## Options considered

Alternatives not documented, to confirm. Implied options: delete everything directly, or let the user pick any path. Both were avoided.

## Decision

- Every deletion is confirmed first.
- Only paths strictly inside the home folder pass `isSafeToDelete` (never the home folder itself); symlinks are resolved first.
- Large files and uninstalled apps go to the Trash; caches and rebuildable folders are deleted directly after confirmation.
- A dev folder (`node_modules`, `.build`, `Pods`...) is suggested only when its project file is next to it; `build/` and `dist/` are never suggested.
- The uninstaller matches leftovers by exact bundle identifier and refuses Apple apps and running apps.

## Consequences

- Good: a small, testable rule set; user trust.
- Bad: some real caches are not cleaned (the app prefers false negatives).
- Risks: **new cleaners (Docker, OrbStack, simulators) are not file folders and may not fit this model** (risk 2 in `ARCHITECTURE.md`).

## Revisit when

A cleaner is added whose targets are not plain files under the home folder.

## Open points

- The model for non-file targets (running containers, shared volumes) is undecided.
