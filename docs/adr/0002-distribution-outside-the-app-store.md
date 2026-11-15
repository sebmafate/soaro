# 0002. Distribute outside the Mac App Store, not sandboxed

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | unknown; before 1.0.0 (2026-11-15) |
| Drives from | the cleanup and monitoring features need access to the user's files and system data |

## Context

Soaro scans the home folder, empties the Trash through Finder, reads process and network information and private sensors. The App Store requires the sandbox, which would block this. Evidence: README "Limits" ("not sandboxed, so it cannot be on the Mac App Store"), `scripts/Soaro.entitlements` (only the Apple Events entitlement), `scripts/build-app.sh`.

## Options considered

### Option A: Mac App Store with the sandbox
- For: discovery, automatic updates.
- Against: cannot do the cleanup or most sensors. **Not documented as evaluated; inferred.**

### Option B: Developer ID, notarized DMG on GitHub
- For: full access, direct control of releases and updates.
- Against: user must trust a download; needs an Apple Developer account and notarization.

## Decision

Option B: hardened runtime, Developer ID signature, notarization and stapling, distributed as a DMG on GitHub Releases. Entitlements: Apple Events only (`scripts/Soaro.entitlements`).

## Consequences

- Good: all features are possible; the release chain is under the author's control.
- Bad: no App Store reach; the app asks for macOS permissions (Full Disk Access, automation); an annual Apple Developer fee (the donation goal, see `STATUS.md`).
- Risks: a certificate or notarization problem blocks releases (documented in `docs/releasing.md`).

## Revisit when

A reduced "light" edition without cleanup is wanted for the App Store.

## Open points

- Was the App Store evaluated formally? Unknown.
