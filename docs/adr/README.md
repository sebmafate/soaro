# Architecture decision records

One decision per file. An accepted ADR is never edited: a new one supersedes it.

| ADR | Decision | Status | Date |
| --- | --- | --- | --- |
| [0001](0001-native-swift-menu-bar-app.md) | Native Swift menu bar app, macOS 14+, Apple silicon only | accepted (reconstructed) | unknown |
| [0002](0002-distribution-outside-the-app-store.md) | Distribute outside the Mac App Store, not sandboxed | accepted (reconstructed) | unknown |
| [0003](0003-sparkle-updates-and-appcast-as-release-asset.md) | Sparkle updates; the appcast is a release asset reached through a redirect | accepted (reconstructed) | unknown |
| [0004](0004-history-in-sqlite.md) | History in SQLite through the C API | accepted (reconstructed) | unknown |
| [0005](0005-defensive-sensor-readings.md) | Read hardware sensors through private interfaces, hide what fails | accepted (reconstructed) | unknown |
| [0006](0006-cleanup-safety-model.md) | Confirmed, home-folder-only deletion; Trash when recoverable | accepted (reconstructed); completed by 0009 | unknown |
| [0007](0007-privacy-by-default.md) | Nothing leaves the Mac by default | accepted (reconstructed) | unknown |
| [0008](0008-release-built-on-github-actions-xcode-26.md) | Release built by GitHub Actions on Xcode 26 | accepted (reconstructed) | unknown |
| [0009](0009-cleanup-actions-by-supported-route-under-one-contract.md) | Cleanup actions that are not plain deletion: the supported route per target, under one contract | accepted | 2026-11-15 |
| [0010](0010-docker-targeted-prune-measured-by-host-space.md) | Docker: a targeted prune through the docker command, measured by the space returned to the Mac | proposed (pending Test B) | 2026-11-15 |
