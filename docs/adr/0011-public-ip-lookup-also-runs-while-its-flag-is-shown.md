# 0011. The public IP lookup also runs while its flag is shown in the menu bar

| | |
| --- | --- |
| Status | accepted |
| Date | 2026-11-18 |
| Decided by | the author, on 2026-11-18, when the country flag in the menu bar (SL19) was built |
| Supersedes | none. **Extends [0007](0007-privacy-by-default.md), does not supersede it:** the lookup stays optional and off by default, with the same service (ipwho.is, backup ipapi.co), the same session (ephemeral, no cookies, no cache) and nothing stored |
| Drives from | decision driver 3 (privacy); the SL19 flag |

## Context

ADR 0007 makes the public IP and country lookup optional and off by default. Until now the code only asked the service while the Network tab was open (panel or window), at most every 5 minutes, or at once when the user switched the setting on or pressed "Refresh". The Settings text said so: "only while the Network tab is open".

SL19 shows the flag of the public IP's country in the menu bar, to the right of the network rates. The flag only reads what the lookup found. With the old rule it was only as fresh as the last time the Network tab was open: after a restart it was absent, and after a VPN change it kept showing the old country, a wrong answer in the one place that is always on screen.

## Options considered

### Option A: keep the stale flag

- For: nothing changes in what the setting does; no new text.
- Against: a flag that shows the wrong country after a VPN change is worse than none; after a restart it is missing until the tab is opened.

### Option B: refresh while the flag is shown (chosen)

- For: the flag follows the network and the VPN within a few seconds; the user already asked for the lookup by turning the setting on; no new setting and no new service.
- Against: the service is asked when no Soaro window is open, so the setting now means "ask while I look at the country in the menu bar", not only "while I look at the tab". The Settings text must say so.

### Option C: a separate setting for the flag

- For: the flag could be on without any lookup beyond the tab.
- Against: a second opt-in for one idea, and the old behaviour (a stale flag) would come back as the default of that setting.

## Decision

**Option B.** The lookup also runs while **the flag is displayed**, that is, when "Show public IP and country" is on **and** the network item is shown in the menu bar (a rate is measured). Rules that do not change: never in demo mode, never when the setting is off, one lookup at a time, the same endpoints and session, nothing stored on disk, at most one request every 5 minutes unless the connection changes (another local address, a VPN switched on or off), and then at once but not more than every 5 seconds. New rules:

1. The decision is one pure function, `PublicIPLookupPolicy.shouldLookUp`, with injected time; the Network tab path uses the same function and keeps its exact rules (a test compares it with the old rule on a grid of inputs).
2. It is driven by the existing 3-second measure of `AppState`; no new timer, no new thread. The local VPN detection (no network request) also runs every 10 seconds while the flag is shown, so a VPN change is seen with the tab closed.
3. After a failed lookup, no retry before 60 seconds when only the flag asks (the Network tab keeps its old rules).
4. The flag is shown only if the last reply is at most **1 hour** old and was taken on the current connection (same local address and VPN state). Otherwise no flag: better none than a wrong one. The Network tab keeps showing the last reply as before.
5. Turning the setting off stops everything at once: the reply is forgotten, a lookup in flight is discarded when it comes back, the flag disappears. Hiding the network item stops the lookups it caused.
6. The text under the setting, the README (English and French) and the site are corrected to say it.

## Consequences

- Good: the flag is true; the user sees the country they are really in; no new setting.
- Bad: with the setting on and the flag shown, Soaro asks a third-party service about every 5 minutes for as long as it runs, not only when a window is open. That service sees the public IP each time. This is stated in the Settings text and in the README.
- Risks: a failing service makes Soaro retry once a minute at most while the flag is shown (the 60-second pause), and no flag is shown meanwhile once the last reply is over an hour old; the lookup service may rate-limit (5 minutes is gentle).

## Revisit when

- The service starts to refuse requests, or the author wants the lookup tied to a visible window again (then Option C or a return to Option A).
- A second feature needs the public IP (then think about a shared, documented rule).

## Open points

- None.
