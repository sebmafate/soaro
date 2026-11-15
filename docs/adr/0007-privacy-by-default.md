# 0007. Nothing leaves the Mac by default

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | unknown; before 1.0.0 |
| Drives from | decision driver 3; the app reads sensitive data (processes, network, serial number) |

## Context

A system monitor sees what runs on the Mac. Users must be able to trust that it does not report it. Evidence: README "Privacy", `PublicIPService.swift`, `Updater.swift` (no system profile), `Diagnostics.swift`, website analytics notes in `docs/website.md`.

## Options considered

Alternatives not documented. Implied: usage analytics or crash reporting, rejected by omission.

## Decision

No account, analytics or tracking in the app. Two optional network features are off by default: latency (ping to 1.1.1.1) and public IP and country (ipwho.is, backup ipapi.co; the reply is validated). VPN detection is local. The update check sends no system profile. The website counts visits with Umami, without cookies, and the app does not.

## Consequences

- Good: a clear promise, simple privacy text, no backend to run.
- Bad: no usage or crash data; bugs are found only through user reports (`--diagnostics` output is shared by hand).
- Risks: any new network call must be opt-in and documented.

## Revisit when

A feature needs a server (sync, shared recommendations).

## Open points

- None.
