# Soaro developer cleanup: design

| | |
| --- | --- |
| Status | draft (Part 1, UX, and Part 2, UI, done) |
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

**S2 as built (SL10): the Android group**

- **Two groups, in this order:** "iOS Simulators", then "Android emulators", each a section of one list with its own rows; the limit menu, the header total ("Devices: N · X", both groups), the footer and "Scan again" are shared. An empty or hidden group is absent. The Delete bar shows when at least one group is listed.
- **Android row:** the device's display name (the AVD name when it has none), "· API 36" after it (or "Unknown system"), then the reason "inactive for N d", "active today" or "activity unknown", then the size ("…" until measured). In SL10 nothing Android is pre-selected (author's decision: not before SL11, which brings the removal); the reason "inactive for N d" is shown and the user may check a non-running row by hand. SL11 turns the pre-selection on (a device inactive for more than the limit, default 60 days), once the author has settled the last-used signal; the wording may then need "about". There is no "older copy" reason for Android. The "last used" date is an approximation taken from files the emulator writes (proposed, pending the author).
- **Device running:** the SL3 unavailable row, "Running · quit it first"; it cannot be checked; VoiceOver reads "…, not selectable".
- **Platform unread:** "Could not read the Android emulators." appears under the "Android emulators" header with a warning icon and the supporting-text colour, and the iOS group stays usable (and the reverse). It covers an unreadable AVD folder and a process list that cannot be read (a running state that cannot be checked is never offered). When the other group is hidden or empty, the message takes the whole screen.
- **No Android SDK:** the Android group does not exist; iOS works as before. **No Xcode tools:** the iOS group does not exist (no "Could not read the iOS Simulators."); if neither group exists, "No simulator or emulator found.". The tool's row in the Cleanup list shows when iOS or an Android SDK is found, and in demo mode.
- **Delete with Android checked (SL11):** Delete is usable when a row is checked in either group (iOS, Android, or both); the rule that disabled it while an Android row was checked is gone. The banner "Nothing to suggest…" does not count the Android group while it is not pre-selected (the switch is still off: the author has not settled the last-used signal, so Android rows are checked by hand and nothing Android is checked for the user); the explanation footer ("…are pre-selected…") is shown only under the iOS section, and the small-devices count under the last section (existing strings); the action bar counts both groups ("Selected: N · X").
- **Mixed confirmation and deletion (SL11):** one confirmation for the whole selection: the existing title "Delete the selected devices? (N)" with N the total of both groups, the existing message with the total size of both groups (it already says devices, snapshots and Android Studio), then the names of the checked devices, one per line after a blank line ("• iPhone 15", "• Test Phone A": iOS first, then Android, in display order, verbatim, at most 8 and then a single "…" line; data, never catalog keys, so no new string; ADR 0009 rule 2), "Delete" as the critical button, Cancel the default. Then one batch: the iOS devices first, then the Android devices, each group in display order, behind the same busy bar ("Deleting…"). An Android device is removed as its registration and its folder together, the folder first (if the folder cannot be removed the device stays listed and can be retried; if the folder goes but a registration cannot be removed, an orphan registration is left that Soaro no longer lists and Android Studio shows as broken, and the toast counts the device as not removed); a running one, or one that started after the scan (by its name or by any alias), is never touched; a device that cannot be checked right before is not removed.
- **Toast combinations as built (SL11):** the freed space first (the sum of both groups), when at least one device was removed, or when nothing failed and iOS did not time out ("0 bytes freed" in English when everything was already gone); then the reason: iOS timed out gives "Xcode’s simulator service did not answer. Try again in a moment.", followed by "Devices that could not be removed: N" when N Android devices were not removed (new combination: iOS timed out plus Android failures; the iOS-only text is unchanged); otherwise exactly one device not removed and it is running gives “Name” is running: quit it first. (the display name, never a catalog key); otherwise any device not removed gives "Devices that could not be removed: N" (running ones included; Back counts the untried ones). A failure or a time-out in one group never stops the other; Back stops both and shows no toast if nothing was tried. An Android "time-out" does not exist: an unavailable process list is "could not be removed". No new key.
- **Android deletion in demo (SL11):** the same confirmation (counting both groups); once confirmed, the checked iOS and Android demo rows leave the list at once, the toast is the sum of their made-up sizes, nothing is launched, measured, read, written or rescanned. The running demo device still cannot be checked.
- **Demo (`SOARO_DEMO=1`):** three made-up virtual devices shown at once, none checked, one running, one under 100 MB in the footer.
- **New text** (3 keys, nine languages, AI-assisted): "API %@", "Android emulators", "Could not read the Android emulators.". The existing "inactive for N d", "active today", "activity unknown", "Running · quit it first" and "Unknown system" are reused.

**S2, interface text as built by SL8 and SL9 (iOS group only)**

- **Older copy:** the reason names the device that is kept, in the device's own name (never a catalog key): "older copy of “iPhone 17”, used 4 d ago", "…, used today" or "…, which is running". It follows the days part with " · " ("inactive for 25 d · older copy of “iPhone 17”, used 4 d ago"). An unavailable device adds "unavailable: system not installed".
- **Days part:** "inactive for N d" (N of 1 or more), "active today" (0), "activity unknown" (no date).
- **Group label and system:** one group "iOS Simulators" for all Apple platforms; each row shows its system after the name ("· iOS 26.2", "watchOS 11.2", "tvOS 18.2"); `xrOS` is shown as "visionOS"; an unreadable identifier is "Unknown system". The word "runtime" never appears.
- **While the sizes are measured:** the header shows a small spinner and "Measuring sizes…" instead of the total; each size reads "…" until measured; rows keep the listing order (name, system) and are sorted by size once, when the last size arrives. When done the header reads "Devices: N · X". A small device (under 100 MB) leaves the list as soon as its size is known.
- **Neutral messages** (never an exit code, an error output or a path): "Could not read the iOS Simulators." (tool absent, command failed, output unreadable), "Xcode’s simulator service did not answer. Try again in a moment." (time-out), "No simulator or emulator found." (no device at all). The header, the limit menu and "Scan again" stay usable in every state.
- **Running device:** the SL3 unavailable row with "Running · quit it first"; VoiceOver reads it as "Running · quit it first, not selectable".
- **Banner timing:** the banner "Nothing to suggest at N days…" is hidden while sizes are measured (the pre-selection is provisional until the last size arrives) and shows only when at least one row is listed and nothing is pre-selected. "Scan again" is disabled during the listing, and a repeated trigger starts no second `simctl list`; during the measuring it cancels the measuring and starts again.
- **Known gap:** the summary of the shared `ActionBar` ("Selected: N · X") still uses `.secondary` until SL4 applies the supporting-text token app-wide.
- **Header:** "Devices: N · X", the menu "Inactive for more than" with 30, 60, 90 and 180 days, "Scan again"; it may wrap onto a second line in the panel. The Delete button is live since SL9 (see the bullets below).
- **Focus and reading order (as built):** limit menu, Scan again, the rows top to bottom, then Delete. This differs from the order written in the accessibility rules below (rows before Scan again); the header comes first on screen, so the focus order follows it.
- **When Delete is available (SL9):** the list is shown, every size is measured, at least one device is checked, and no deletion is running. While the sizes are measured, with nothing checked, or while deleting, the button is disabled. The bar is destructive-tinted, has no keyboard shortcut and is never the default action: Return does nothing; the confirmation (S3) has Cancel first and as default.
- **Confirmation (S3) for simulators:** title "Delete the selected devices? (N)"; message "X will be freed. The devices, the apps and data on them, and their snapshots will be deleted. You can create new devices from Xcode or Android Studio."; buttons Cancel (default) and Delete (destructive, no key). Cancelling changes nothing and shows nothing.
- **Deleting state:** the bar shows a small spinner and "Deleting…" in place of the selection summary, the button is disabled, the limit menu and "Scan again" are disabled, and tapping a row does nothing. The running row stays "Running · quit it first". Each device is re-checked right before its delete (about 1 s per device). When the batch ends, the toast appears and the list is read again with a new pre-selection.
- **Result toast (partial failure and tool too slow):** parts joined with " · ", the freed space first ("X freed", shown when at least one device was removed, or when nothing failed (and none was left untried by Back): "0 bytes freed" in English if all were already gone). Then one of: "Xcode’s simulator service did not answer. Try again in a moment." (a time-out stops the batch), "“iPhone 15” is running: quit it first." (exactly one failure, and it is a running device; the name is the device's own, never a catalog key), or "Devices that could not be removed: N" (any other failure; N counts every device not removed, running ones included). A device already removed by someone else is neither a removal nor a failure. If the simulator service cannot be asked, the batch stops and every remaining device counts as not removed.
- **Back during a deletion:** the device in progress finishes, no other starts, and the screen is left "not scanned": the next opening scans again and never shows a stale list. The toast says what was done without claiming more: the devices that were never tried are counted with the failures ("X freed · Devices that could not be removed: 2"), and if Back came before any attempt there is no toast. If the tool is opened again (or from the other surface, panel or window) while the batch still runs, the screen reads "Deleting…" instead of "Looking for simulators and emulators…", Delete and "Scan again" are disabled, and the scan starts by itself when the batch ends. Leaving the Cleanup tab does not stop the batch: its toast still appears.
- **Demo deletion:** the same confirmation is shown (so S3 can be captured); if confirmed, the checked made-up rows leave the list at once and the toast is the sum of their made-up sizes "freed". Nothing is launched, measured, read or written, and the list is not read again.
- **Text colour:** every supporting text of this screen (sizes, header summary, footer, "Measuring sizes…", messages) uses the supporting-text token (`supportingText()`), with Increase Contrast; the reason line stays in primary text.

**S1, as built by SL6 (the NuGet row)**

- **Position and text:** after "Cargo cache (Rust)" and before "Xcode iOS DeviceSupport" in Developer; title "NuGet packages", detail "Downloaded packages, downloaded again when needed" (the npm text). The row is shown only when the folder exists and holds something (size above 0); the existing `CleanupRow` states are unchanged.
- **Confirmation (S3):** unchanged text: title "Clean “NuGet packages”?", message "• NuGet packages", then "About 13 GB will be freed." (size of the last scan). **Toast:** unchanged rules: "13 GB freed", with " (N items in use were skipped)" when some were; the first error replaces it. In demo mode the toast shows the demo size and nothing is deleted. The same holds in the four tools (Large files, Inactive projects, Uninstaller, Startup items): the confirmation is shown with the same texts, then the rows leave the list and the toast shows the made-up size, with no file moved and no system command run; the Overview "Quit" button only shows its toast.

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

Small on purpose: every screen of Part 1 is built from components that already exist in the app. No new custom component, no new palette. This part records the roles the app already uses, the contrast measured for them, and the small changes agreed on 2026-11-15 (the "accessibility lot") that go into shared components.

## Platform and conventions

- **Platform:** macOS 14+, SwiftUI with some AppKit (ADR 0001).
- **Containers:** the menu bar panel (fixed 430 x 640 pt, flat cards) and the standalone window (860 x 680 pt, minimum 700 x 520, glass cards: Liquid Glass on macOS 26, translucent material on 14 and 15).
- **Conventions that apply:** a tool opens in place with a "Cleanup" back button; selection lists use the plain list style; confirmations are native alerts (`AppState.confirm`); results are a toast; progress is a small spinner; everything follows the system appearance (light, dark), accent colour and Increase Contrast setting.

## Identity

Native, calm, readable. The navy and teal of the icon (#16395C, #1F8F8C) stay in the icon and the website; the interface uses the system accent colour. No identity work is needed for this feature.

## Tokens

### Color

All roles are the system's semantic colors, so both themes come from the system. Ratios are computed (`WCAG` relative luminance) against reference backgrounds, white and #1E1E1E. The real backgrounds are translucent materials that change with the desktop, so the ratios are approximate.

| Role | Light | Dark | Contrast of text on the background | Use |
| --- | --- | --- | --- | --- |
| background | system window or material | system window or material | n/a | screens |
| surface | card (flat in the panel, glass in the window) | same | n/a | cards |
| text-primary | system label (85 %) | system label (85 %) | 15.1 : 1 light, 12.3 : 1 dark | names, reasons, messages, anything the user needs |
| text-secondary | system secondary label | system secondary label | **3.95 : 1 light**, 5.9 : 1 dark | supporting detail and units only; below AA for small text in light mode |
| text-tertiary | system tertiary label | system tertiary label | **1.84 : 1 light**, 2.27 : 1 dark | decoration only; never information |
| text-supporting (new) | text-primary at 56 % opacity | text-primary at 56 % opacity | about 4.95 : 1 light, 6.1 : 1 dark (70 % with Increase Contrast: 8.45 : 1 and 8.78 : 1) | supporting text everywhere in the app: units, sub-lines, footers, group headers. Replaces text-secondary for text |
| accent | system accent (blue by default) | same | checkmark 4.02 : 1 light, 4.57 : 1 dark (UI component, needs 3) | selected check, links, default buttons |
| danger-fill | #D32F2F | #D32F2F | white label **4.98 : 1**; fill against background 4.98 : 1 light, 3.35 : 1 dark | the destructive button (replaces the system red, 3.55 : 1 light and 3.41 : 1 dark with a white label) |
| danger-fill, Increase Contrast | #B71C1C | #B71C1C | white label 6.57 : 1 | used when the system asks for more contrast |

Rules (decided 2026-11-15): essential information is text-primary; supporting text is text-supporting, everywhere in the app; text-secondary stays only for icons and decoration, where 3 : 1 is enough; text-tertiary is never used for information (the two existing text uses move to text-supporting; chevrons stay tertiary). The empty selection circle uses text-secondary (3.95 : 1 and 5.9 : 1, above the 3 : 1 needed for a component).

### Typography, spacing, shape, motion

| Token | Value | Notes |
| --- | --- | --- |
| tool title | `.headline` | as the other tools |
| row name | `.callout` | one line, truncated at the end, full name in a tooltip (`.help`) |
| reason line | `.caption`, text-primary | agreed change: the other tools use `.caption2` and secondary |
| size | `.caption` with monospaced digits, text-supporting | right-aligned, never truncated |
| group header | `SectionHeader` (existing), now `.caption` in text-supporting | changed in the accessibility slice |
| footer note | `.caption2`, text-supporting | supporting only; the essential parts of it are also in the confirmation |
| spacing | 14 pt screen padding; 10 pt card padding; 4 pt row padding; 12 pt between blocks | as in the code |
| shape | flat card radius 10; glass card radius 16 (continuous) | existing `cardBackground` |
| motion | none added | the spinner is the only motion; see rule on reduced motion |

## Components

| Component | Native or existing | Variants | States |
| --- | --- | --- | --- |
| Tool row in the Tools list (S1) | existing button row | none | default, hover, pressed, focus |
| `CleanupRow` (NuGet, S1) | existing | none | default, busy (spinner), size unknown ("—"), disabled when size is 0 |
| `SelectionRow` | existing, made shared (it is `private` today) | **new: unavailable** (running device, image in use) with a `minus.circle` icon and a text reason | default, selected, unavailable, focus (system focus ring), pressed |
| `ActionBar` | existing, made shared | destructive (danger-fill); **new: busy** (spinner beside the summary) | default, disabled (nothing selected), busy |
| `SectionHeader` | existing | none | default |
| `EmptyHint` | existing | `info.circle` for information; `exclamationmark.triangle` for "could not read" | default |
| Limit menu "Inactive for more than" | native `Picker` (menu), as the size limit of Large files | 30, 60, 90, 180 days | default, focus |
| Scanning state | native `ProgressView` with a caption | none | loading |
| Confirmation (S3) | native `NSAlert` through `AppState.confirm` | destructive: `critical: true` | default |
| Toast | existing | none | visible 4 s |

Every screen of Part 1 uses only these. There is no custom component. The two extensions (unavailable row, busy bar) are small variants of existing components.

## Accessibility rules

- **Target size:** at least 24 x 24 pt for every control (WCAG 2.2, criterion 2.5.8). Checked on 2026-11-15: the Apple HIG gives no minimum for macOS controls (its general 44 x 44 pt rule is for touch), so WCAG 2.2 is the project's rule. The selection check, about 22 pt today, grows to 24 pt in the shared `SelectionRow`.
- **Text scaling:** use text styles only; add no fixed font size. Whether macOS offers system-wide text scaling to third-party apps stays unconfirmed: the only source found is a community forum reply saying Dynamic Type is not available to third-party apps on macOS. To test by hand on a recent macOS (System Settings, Accessibility, Display, Text size: is Soaro listed?).
- **Screen reader:** one element per row. The label contains the device name, the platform and system, the size and the reason, then "selected" or "not selected" as its value. An unavailable row reads "running, not selectable". The shared selection button no longer says only "Selected"; it names the device. Results (the toast) are also announced, because the toast disappears after 4 seconds.
- **Keyboard and focus:** every row and button is reachable with Full Keyboard Access; Space toggles a focused row; focus order follows reading order (limit menu, rows top to bottom, Scan again, Delete).
- **Confirmation default (decided 2026-11-15):** the default button of a confirmation is never the one that deletes. Cancel is the default button, so pressing Return never deletes. The rule applies to every confirmation of `AppState.confirm`, not only to those marked `critical`: all five existing callers (cleanup, Trash, inactive projects, uninstall, login items) remove something, and so will the new ones. Today the first button, which is the destructive one, is the default, so Return deletes; this changes the existing alerts too. The `critical` flag keeps controlling only the alert style.
- **Reduced motion:** the tool adds no animation. The existing toast slides in with a 0.2 s transition regardless of the setting; it should drop the slide when Reduce Motion is on.
- **Color is never the only signal:** selected is a filled check against an empty circle; unavailable is an icon and a text; an unreadable platform is an icon and a text; the destructive button says "Delete".
- **Increase Contrast:** the system colors adapt by themselves; danger-fill switches to its darker value.
- **Localisation:** nine languages (en, fr, de, es, it, pt-BR, ja, zh-Hans, ko), none right-to-left, so mirrored layout is out of scope. Long translations truncate the device name and never the size or the unit.

## Adaptive layout

- **Panel (430 pt wide):** a device row is the checkbox, the name and the reason on two lines, and the size. The name truncates; the size does not. The limit menu and "Scan again" share the header line and may wrap onto a second line in a long translation.
- **Window (700 pt wide or more):** the same layout with more room; no extra columns.
- No other sizes or devices are in scope.

## Verification of this part

- Every screen S1 to S3 uses only the components and tokens above (S4 Docker and S2b images are not designed yet).
- Contrast is recorded for each text and background pairing in both themes (approximate, against reference backgrounds).
- No custom component, so nothing to justify beyond the two small variants.

## Open points (UI)

- **Accessibility slice (decided 2026-11-15), to plan before the tool itself:** (1) Cancel as the default button in `AppState.confirm`, with a test; (2) toasts: plain fade with Reduce Motion and a VoiceOver announcement in `AppState.showToast`; (3) the text-supporting color replaces `.secondary` for text across the app (69 uses in 11 files), including `SectionHeader` and the two informative `.tertiary` texts (`CleanupToolViews.swift:87`, `NetworkTab.swift:106`); (4) shared `SelectionRow` and `ActionBar`. One `CHANGELOG` entry. The only visible change is a slightly darker grey for supporting text.
- Still to test by hand, not fixable by code: text scaling on a recent macOS (is Soaro listed in the Text size settings?); real contrast on the glass and material backgrounds, with Reduce Transparency and Increase Contrast on.
- Cancel as the default button is decided and applies to all five existing confirmations. For delivery: build the alert (buttons and default) separately from showing it, so a unit test can check that the default is Cancel.
- The toast slide transition and VoiceOver announcements apply to every toast, not only the new tool.
- Real contrast on the glass and material backgrounds is not measured; the ratios above use plain references.

## Change log

| Date | Change |
| --- | --- |
| 2026-11-15 | Part 1 (UX) written |
| 2026-11-15 | Decision by the author: an accessibility slice before the tool, with the text-supporting color applied across the app (not only in the new tool) |
| 2026-11-15 | Decision by the author: a delete button is never the default button of a confirmation; Cancel is the default for all confirmations |
| 2026-11-15 | Part 2 (UI) written: roles and contrast, the accessibility lot (shared `SelectionRow` and `ActionBar`, reason line in primary text at `.caption`, danger-fill #D32F2F), accessibility rules |
| 2026-11-16 | SL3: text-supporting is defined as pure black (light) or pure white (dark) at an absolute alpha of 0.56 (0.70 with Increase Contrast), because "primary at 56 %" starts from a label color that is itself about 85 % opaque and would give about 3.6 : 1 on white. Factual note, the decision is unchanged |
| 2026-11-16 | SL8: interface text of S2 as built (older copy names the kept device, "Measuring sizes…", neutral messages, group label and system label, focus order). Factual notes, no decision changed |
| 2026-11-17 | SL6: S1 as built (NuGet row after Cargo, confirmation and toast texts unchanged, demo mode deletes nothing). Factual notes, no decision changed |
| 2026-11-17 | SL9: S2 as built for deletion (when Delete is available, the deleting state, the toast combinations, Back during a deletion, demo deletion) and the confirmation text of S3 for simulators. Factual notes, no decision changed |
| 2026-11-17 | SL9 fix round: S2 as built for Back (honest toast), reopening during a batch, and leaving the tab. Factual notes, no decision changed |
| 2026-11-17 | SL10: S2 as built for the Android group (two groups and their order, the Android row text, platform unread, the iOS group hidden without Xcode, Delete with an Android row checked, demo). Factual notes, no decision changed |
| 2026-11-17 | SL11: S2 as built for Android deletion (Delete usable with an Android row checked, the mixed confirmation, the toast combinations including iOS timed out plus Android failures, Android deletion in demo). Factual notes, no decision changed |
| 2026-11-17 | SL11 review round: S3 as built names the checked devices after the localized text (no new string); the orphan-registration case is stated. Factual notes, no decision changed |
