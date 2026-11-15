# 0004. History in SQLite through the C API

> Reconstructed on 2026-11-15 from the code and history. To be confirmed.

| | |
| --- | --- |
| Status | accepted (reconstructed) |
| Date | unknown; before 1.0.0 |
| Drives from | idle cost (ADR 0001), charts over 1 hour to 30 days |

## Context

The history tab shows charts over 1 hour, 24 hours, 7 days and 30 days. Raw samples every 3 s would be too many, so rows are aggregated (~30 s) and pruned after 30 days. Evidence: `HistoryStore.swift` (`sqlite3_open`, WAL, `retention = 30 * 86_400`), `AppState.record`. **Rationale confirmed by the author:** lightness and control.

## Options considered

### Option A: SQLite through the C API (chosen)
- For: no extra dependency, small memory, full control of aggregation and retention. Against: hand-written SQL and error handling.

### Option B: SwiftData or Core Data
- For: less code. Against: heavier, and tied to newer OS versions. Not evaluated in detail, reasons given by the author in general terms.

## Decision

SQLite with the system library, WAL mode, one aggregated row per ~30 s, 30-day retention.

## Consequences

- Good: tiny footprint, tests with an in-memory or temporary database (`HistoryStoreTests`).
- Bad: schema migrations are manual; a failure to open the database silently disables history (`history?`).

## Revisit when

A schema change or a sync feature (several Macs) is needed.

## Open points

- None for the decision; the schema-migration plan does not exist yet.
