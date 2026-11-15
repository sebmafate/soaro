# 0005. Read hardware sensors through private interfaces, hide what fails

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | unknown; before 1.0.0 |
| Drives from | the Performance and Battery tabs (temperatures, fans, power draw) |

## Context

Apple offers no public API for CPU temperatures, fan speeds or system power. Apps read them through HID and SMC. These interfaces are undocumented and can change with any macOS release. Evidence: `Samplers/SensorSampler.swift`, `docs/architecture.md` ("Defensive sensors"), README "Limits", `SMCDecodingTests`.

## Options considered

### Option A: private HID and SMC readings, failures hidden (chosen)
- For: the data users expect from a monitor. Against: fragile.

### Option B: public metrics only
- For: stable. Against: no temperatures, fans or power: a much weaker monitor.

## Decision

Read through HID and SMC; every read can fail; a failed read hides the section instead of showing wrong data. Slow sensors are read every 9 s (every 3 s when the tab is visible).

## Consequences

- Good: honest display; the rest of the app keeps working when a sensor breaks.
- Bad: new Macs or macOS versions may silently lose readings; decoding is covered by tests on sample data, not on real hardware.
- Risks: noticed only by manual testing on each macOS beta. The author lists this as a fragile area.

## Revisit when

Apple publishes an API, or a macOS release breaks the readings.

## Open points

- No automated check on real hardware.
