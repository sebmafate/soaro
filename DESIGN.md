# Soaro developer cleanup: design

| | |
| --- | --- |
| Status | draft (Part 1, UX, done; Part 2, UI, to do) |
| Version | 0.1 |
| Date | 2026-11-15 |
| Based on | `SPEC.md` v0.3, `ARCHITECTURE.md` v0.2 |
| Interface language | English first, then the eight other languages of the app (R12) |

This design covers only the developer cleanup. It reuses the existing Cleanup tab: a list (System, Developer, Tools), a tool opens with a "Cleanup" back button, tools show a selection list and an action bar.

# Part 1: UX

## Users and context

| User | Job to be done | Context | Frequency |
| --- | --- | --- | --- |
| The author (.NET, Swift and cloud developer) | Free the space that development takes, knowing what is deleted | On the Mac, in the Soaro window or the menu bar panel, a few minutes, full attention (a chosen chore) | About once a month (success criterion S1) |
| Another Mac developer using Soaro | The same, or ignore the section | Same | Rare |

## UX goals

1. **Few actions:** from opening the tool to a confirmed removal of the pre-selected devices, at most 3 actions (open the tool, Delete, confirm).
2. **Every row says why:** no device is pre-selected without a readable reason.
3. **Nothing is deleted without a confirmation** that names the target, its size and what is lost (R8).
4. **The result is honest:** the space really freed is shown, not the announced one (R7).
5. **A missing or failing tool breaks nothing:** the entry hides, or says what could not be read, with no empty screen and no technical message (R6).

## Journeys

| ID | Journey | Trigger | Steps | Outcome | Main failure path | Requirements |
| --- | --- | --- | --- | --- | --- | --- |
| J1 | Discovery (first run) | Opens the Cleanup tab after the update | 1. Sees the **NuGet packages** row (Developer) and the **Simulators and emulators** row (Tools) | New tools visible with no setup. On a Mac without Xcode simulators, Android SDK or NuGet folder, nothing new appears | Tool not found: the row is simply not shown | R6, R18 |
| J2 | Clean NuGet | Wants the 13 GB | 1. Clean on the row. 2. Confirm | "13 GB freed" (space really freed) | Folder not accessible: existing short message | R1, R7, R8, R13 |
| J3 | **Clean simulators and emulators** (critical moment) | Disk filling up, or the monthly chore | 1. Open the tool (the scan starts by itself). 2. Review the list (pre-selected rows are checked). 3. Delete. 4. Confirm | Chosen devices leave the list; the space really freed is shown | A device is running (not selectable, explained); the tool is too slow; partial removal | R3 to R9, R16 to R18 |
| J4 | Adjust what is pre-selected | The 60-day limit does not fit | 1. Change "Inactive for more than". 2. Pre-selection is recomputed. 3. Continue as J3 | Selection follows the new limit | Nothing at that limit: "Nothing to suggest" banner | R3, R16 |
| J5 | Android system images (Should) | A removed AVD leaves an unused image | 1. In the same tool, group "Android system images". 2. Check an unused image. 3. Delete. 4. Confirm, with the download-again warning | Image removed | Image still used: not selectable, names the AVD | R19 |
| J6 | Docker (Should, after Test B) | Engine running | Separate tool, designed only if Test B passes | not designed | Engine stopped: section hidden or "engine stopped" | R10, R11 |

## Information structure

- **Names (one per thing):** the tool is **Simulators and emulators**; an item is a **device** (groups "iOS Simulators" and "Android emulators"); the reason is **inactive for N d** or **older copy**; a checked row is **pre-selected**; the limit is **Inactive for more than N days**; an Android image is a **system image** (iOS runtimes are out of scope, so the word "runtime" is not used).
- **Relations:** a platform group contains devices; an Android device depends on a system image; an image used by a device cannot be removed before that device.
- **Navigation:** the existing one. The Cleanup list opens a tool; "Cleanup" goes back. Two levels, no new depth.
- **Placement decision (2026-11-15):** NuGet is one row in **Developer**; one tool **Simulators and emulators** in **Tools** covers iOS and Android, and later the Android system images as a group; Docker would be a separate tool.

## Screens

| ID | Screen | Purpose | Entry points | Primary action | States covered | Requirements |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | Cleanup list (existing, changed) | Adds the NuGet row and the tool row | Cleanup tab | Clean (NuGet); open the tool | first use (new rows); tool absent (rows hidden); busy (spinner); error (short message) | R1, R6, R13 |
| S2 | Simulators and emulators (new) | Choose and delete devices | Row in S1, or an advice | Delete (action bar) | scanning; no device; nothing pre-selected; device running; platform unreadable; deleting; partial failure; result | R3 to R9, R16 to R18 |
| S3 | Confirmation (existing alert) | Last guard before deleting | Delete in S2, Clean in S1 | Confirm or cancel | one variant per kind of target | R8 |
| S2b | "Android system images" group, inside S2 (Should) | Remove an unused image | S2 | Delete | image in use (not selectable); download-again warning | R19 |
| S4 | Docker (Should, after Test B) | not designed | S1 | not designed | not designed | R10, R11 |

### Wireframes

**S1 (the two new rows)**

```
 DEVELOPER   Xcode DerivedData · npm · Gradle · Cargo · ...
             NuGet packages                          13 GB  [Clean]
 TOOLS       Large files                                      >
             Inactive projects                                >
             Simulators and emulators                         >
             Uninstall apps                                   >
             Startup items                                    >
```

**S2, with data from the author's Mac (test A)**

```
+--------------------------------------------------------------------+
| < Cleanup                 Simulators and emulators                 |
|--------------------------------------------------------------------|
| Devices: 12 · 31.4 GB   Inactive for more than [60 days v] [Scan again] |
|--------------------------------------------------------------------|
| IOS SIMULATORS                                                     |
| (x) iPhone 16 · iOS 26.2                                   4.6 GB  |
|     inactive for 66 d                                              |
| (x) iPad Pro 13-inch (M4) · iOS 26.2                       4.0 GB  |
|     inactive for 65 d · older copy                                 |
| (x) iPhone 17 Pro Max · iOS 26.2                           2.2 GB  |
|     inactive for 115 d · older copy                                |
| ( ) iPhone 17 Pro · iOS 26.2                               2.0 GB  |
|     inactive for 10 d                                              |
|                                                                    |
| ANDROID EMULATORS                                                  |
| ( ) Pixel_9a · API 36                                      11 GB   |
|     inactive for 54 d                                              |
| (x) ap34 · API 34                                         1.6 GB   |
|     inactive for 23 d                                              |
|                                                                    |
| 26 small devices (0.5 GB) not shown.                               |
| Devices inactive for more than 60 days, and older copies of the    |
| same model, are pre-selected. A removed device takes its apps,     |
| data and snapshots with it; create a new one from Xcode or         |
| Android Studio.                                                    |
|--------------------------------------------------------------------|
| Selected: 7 · 18.3 GB                                  [ Delete ]  |
+--------------------------------------------------------------------+
```

Each group is sorted by size, largest first. Devices under 100 MB are not listed and are counted in the footer. The row example for ap34 is illustrative.

**S2 states**

```
Scanning         (spinner)  Looking for simulators and emulators…
No device        (ok)       No simulator or emulator found.
Nothing checked  banner     Nothing to suggest at 60 days. Pick devices yourself, or lower the limit.
Device running   ( - ) iPhone 15 · iOS 26.2     3.1 GB    not selectable
                       Running · quit it first
Platform unread  ANDROID EMULATORS
                       Could not read the Android emulators.   (the iOS group stays usable)
Deleting         action bar disabled with a spinner; the list updates at the end
```

**S3**

```
+--------------------------------------------------+
| Delete the selected devices? (7)                 |
|                                                  |
| 18.3 GB will be freed. The devices, the apps and |
| data on them, and their snapshots will be        |
| deleted. You can create new devices from Xcode   |
| or Android Studio.                               |
|                                                  |
|                       [ Cancel ]  [ Delete ]     |
+--------------------------------------------------+
```

## Interface text

Tone: short, concrete, no marketing; same style as the app ("Your sources are not touched", "Folders that could not be deleted: 2"). An error says what happened and what to do. A destructive action says what is lost.

| Where | Text |
| --- | --- |
| NuGet row (S1) | **NuGet packages**: "Downloaded packages, downloaded again when needed" |
| Tool row (S1) | **Simulators and emulators**: "iOS Simulators and Android emulators" |
| Footer of S2 | "26 small devices (0.5 GB) not shown." then "Devices inactive for more than 60 days, and older copies of the same model, are pre-selected. A removed device takes its apps, data and snapshots with it; create a new one from Xcode or Android Studio." |
| Confirmation (S3) | Title "Delete the selected devices? (7)"; message "18.3 GB will be freed. The devices, the apps and data on them, and their snapshots will be deleted. You can create new devices from Xcode or Android Studio."; button "Delete" |
| After removal | "18.3 GB freed" (space really freed) |
| Partial removal | "Devices that could not be removed: 2" |
| Tool too slow | "Xcode’s simulator service did not answer. Try again in a moment." |
| Device started meanwhile | "“iPhone 15” is running: quit it first." |
| Nothing pre-selected | "Nothing to suggest at 60 days. Pick devices yourself, or lower the limit." |
| System images (Should) | Group "ANDROID SYSTEM IMAGES"; row "API 26 · 3.2 GB, used by ap26" (not selectable); confirmation line "This image will have to be downloaded again (3.2 GB) to create a device with it." |

## Walk-through

- **First-time user (J1, J3):** opens Cleanup, sees the two new entries, opens the tool, waits for the scan, reads reasons, presses Delete, confirms. 3 actions after opening: goal 1 met. Reasons are on every pre-selected row (goal 2). The confirmation names size and loss (goal 3).
- **Returning user:** the list stays in memory during the session (as today); the action re-checks that a device is not running right before removing it (ADR 0009), and says so if one started meanwhile.
- **Friction found and handled:** the vocabulary ("suggested" became "pre-selected", "idle" became "inactive") to match the app; the biggest device that is not pre-selected (Pixel_9a, 54 d) stays visible because groups are sorted by size.
- **Friction accepted:** the tool row shows no size; the first scan waits for the real sizes (R7).

## Open questions (UX)

- If measuring real sizes takes more than about 10 seconds, show rows first and refine sizes as they arrive (as the uninstaller does).
- Should the "Inactive for more than" limit be remembered between sessions? Default: no, like the size limit of "Large files".
- Layout of Docker (S4) and of the Android system images group (S2b) is to finish after Test B and after the Must scope.
- Behaviour in the narrow menu bar panel: long device names are truncated on one line (to check in `ui`).

# Part 2: UI

*To do. Completed by the `ui` skill. The tool reuses the existing components (selection row, action bar, empty hint, card), so Part 2 should stay small.*
