# 0001. Native Swift menu bar app, macOS 14+, Apple silicon only

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | unknown; in place since the first commit of the app, 2026-11-14 (history looks squashed) |
| Drives from | constraint "cheap when idle" (20-35 MB, 1-2% of a core), author's skills (Swift) |

## Context

A system monitor must live permanently in the menu bar, so its own cost matters. It needs low-level access (Mach, IOKit, HID, SMC) and a native look. The author works in Swift and SwiftUI. Evidence: README intro and "Limits", `Package.swift` (`.macOS(.v14)`), `SoaroApp.swift` (`MenuBarExtra`).

## Options considered

Alternatives not documented, to confirm. The realistic ones: a cross-platform shell (Electron or similar), or a native app. Only the native option fits the idle-cost target.

## Decision

A native Swift package: SwiftUI with a `MenuBarExtra` and an AppKit window, macOS 14 Sonoma or later, Apple silicon only (the Intel slice is not built; the release runner is arm64). **Rationale inferred (medium)** from the README figures and the low-level APIs used.

## Consequences

- Good: very small footprint, native look (Liquid Glass on macOS 26 and later), direct access to system APIs.
- Bad: macOS only; Intel Macs excluded; low-level APIs are not documented by Apple (ADR 0005).
- Risks and how we will notice them: a new macOS removes an API; the CI and a manual test on each beta show it.

## Revisit when

Intel support is requested by users, or macOS 14 stops being worth supporting.

## Open points

- Was Intel excluded on purpose or by build setup? The README says "Apple silicon only". To confirm.
