# Soaro developer cleanup: Specification

| | |
| --- | --- |
| Status | validated for the Must scope (simulators, Android emulators, NuGet); the Docker part waits for a test (see Kill criteria) |
| Version | 0.3 (R2 covered by the existing cleaner) |
| Date | 2026-11-15 |

## Summary

Extend the Cleanup view of Soaro so it can free what development piles up on a Mac: Xcode simulators, Android emulators, the NuGet cache, and later Docker. It is for the author first (a .NET, Swift and cloud developer whose disk fills up a little more each month) and for other Mac developers who use Soaro and may ignore it.

## Problem

The author does not clean developer data today. The disk gets fuller over time, and from time to time a manual cleanup is needed. On the author's Mac (read-only measurements, 2026-11-15) the following is not covered by Soaro:

| Target | Size |
| --- | --- |
| Xcode simulator devices (`CoreSimulator/Devices`) | 41 GB (33.8 GB by `simctl`) |
| Docker Desktop data | 24 GB (engine stopped) |
| NuGet package cache | 13 GB |
| Simulator runtimes (outside the home folder) | 31.5 GB, 4 runtimes |
| Android virtual devices (`~/.android/avd`, 6 AVD) | 16 GB (one of them, Pixel_9a, is 11 GB) |
| Android system images (`~/Library/Android/sdk/system-images`, 6 versions) | 18 GB |
| SwiftPM cache | almost empty (52 KB), and already covered by the "App caches" cleaner |

The disk is 926 GB with 102 GB free (12 %). The pain is moderate and slow, not an emergency. The irritant is not knowing what is big and what is safe to delete, mostly for Docker and simulators.

Already covered by Soaro and **not part of this work**: Xcode DerivedData, npm, Gradle and Cargo caches, iOS DeviceSupport, simulator caches, and old `node_modules`, `.build`, `target` and `Pods` folders of inactive projects.

## Goals and success criteria

Soaro sends no data (ADR 0007), so success is observed by the author and in GitHub issues, not measured.

- **S1, use:** for the 2 months after the release, the author runs this cleanup at least once a month instead of doing it by hand.
- **S2, gain:** the first pass frees at least 30 GB on the author's Mac.
- **S3, safety:** zero case of data lost by mistake (a simulator, cache or container the user wanted to keep), on the author's Mac and in GitHub issues. This is also a kill criterion.

Motivation, stated honestly: a real personal need, and the pleasure of building the tool. It is not a market gap (see Prior art).

## Scope

**In (first usable version)**

- NuGet package cache.
- Xcode simulator devices, with the information needed to decide.
- Android virtual devices (AVD), with the same kind of information.

**In, later and conditional (Should)**

- Android system images that no virtual device uses.
- Docker and OrbStack: show usage, clean only build cache and unused images. Starts only after a test (Kill criteria 1).

**Out (non-goals)**

- No automatic or scheduled cleanup: every action is started and confirmed by the user.
- No deletion of Docker volumes or of anything used by a running container. Soaro never starts or stops Docker or OrbStack.
- No deletion outside the home folder in this version (so no simulator runtimes, see Open questions).
- Never delete Docker's disk image file directly.
- No other package managers in this version (pnpm, pip, Homebrew, and so on).
- No other Android SDK parts (platforms, build-tools, the emulator program itself). The Gradle cache is already covered.
- No change to the existing cleaners listed in Problem.

## Requirements

| ID | Requirement (what, not how) | Priority | How to verify |
| --- | --- | --- | --- |
| R1 | The Cleanup view shows the NuGet package cache with its reclaimable size, and lets the user clean it after confirmation. | Must | Unit test on a fake folder tree; manual run on the author's Mac (13 GB) |
| R2 | The SwiftPM cache is cleaned. Already met by the existing "App caches" cleaner, which includes `~/Library/Caches/org.swift.swiftpm`. The configuration folder `~/Library/org.swift.swiftpm` is never touched. | Covered by existing | Unit test: the "App caches" cleaner includes the SwiftPM cache folder and never the configuration folder |
| R3 | The Cleanup view lists every simulator device with its real size on disk, last-used date, runtime and availability. It suggests (pre-selects) devices idle for more than a threshold (default 60 days, adjustable) and older duplicates of the same model and runtime, keeping the most recently used. The other devices stay visible and unselected. | Must | Unit tests on fixture data from `simctl`; the author checks the classification on a sample of 5 devices (done 2026-11-17) |
| R4 | A simulator is removed in the way Apple supports, so the simulator system stays consistent, never by deleting its folder by hand. The confirmation says what is lost (the data of test apps). | Must | Unit test with a fake command runner; manual removal of one disposable device |
| R5 | A running (booted) simulator is never suggested or removed. | Must | Unit test with a booted fixture |
| R6 | Each new cleaner appears only if its tool or data exists on the Mac. A missing tool, a failing command or an unreadable output never breaks the Cleanup view or the app (ADR 0005). | Must | Unit tests: tool absent, command failing, malformed output |
| R7 | The size shown is the space that will really be freed, and after a cleanup the app reports the amount actually freed. | Must | Compare with `df` and `du` on the author's Mac, within 10 % |
| R8 | Every deletion is confirmed first, with the size and the target named. Nothing is deleted without that step. The default button of the confirmation is never the one that deletes: it is Cancel. | Must | Unit tests on the confirmation model, including that the default button is Cancel; review of the call paths |
| R9 | The new cleaners add no network call and send no data. | Must | Review: no new network code; test in demo mode |
| R10 | Docker: when the engine is running, show what uses space (images, build cache, containers, volumes). Clean the build cache and untagged images (pre-selected); other unused images are listed but not pre-selected. Never touch volumes or anything a running container uses. | Should | Unit tests with fake command output; real test on the author's Docker Desktop (the spike) |
| R11 | After a Docker cleanup, the app reports honestly how much space came back on the Mac, even if the disk image did not shrink. | Should | The spike (Test B), then a test on measured numbers |
| R12 | New texts are translated in the nine languages of the app. | Should | Translation catalogs complete (existing validation); review by the author |
| R13 | New cleaners are never part of the "quick clean" (as dependency caches are not today). | Should | Unit test on `includedInQuickClean` |
| R14 | The recommendations point to these cleaners when the disk is low and they are large. | Could | Unit test on the recommendation engine |
| R15 | OrbStack support. The author has no OrbStack, so it cannot be verified. | Could | Not verifiable on the author's Mac; needs a tester |
| R16 | The Cleanup view lists every Android virtual device with its real size on disk, an approximate last-used date, its system image and whether it is running. It suggests (pre-selects) devices idle for more than the same adjustable threshold as simulators (R3); the others stay visible and unselected. | Must | Unit tests on fixture AVD folders; the author checks the list against Android Studio on his Mac (6 AVD) |
| R17 | A virtual device is removed with its registration, so its configuration and its files go together, never by deleting only its folder. A running emulator is never suggested or removed. The confirmation says what is lost (the device and its snapshots). | Must | Unit tests with a fake command runner and a running-emulator fixture; manual removal of one disposable AVD |
| R18 | Soaro finds the Android SDK itself (environment variables, then the default location), because its tools are usually not in the PATH. With no SDK, nothing Android appears (R6). | Must | Unit tests: variable set, default path, no SDK; real run on the author's Mac, where the tools are not in the PATH |
| R19 | The Cleanup view lists Android system images with their size and which virtual device uses them. An image is suggested only if no device uses it, and the confirmation says it must be downloaded again (size shown) to recreate a device. | Should | Unit tests on image-to-device matching; manual check on the author's 6 images |

## Constraints and preferences

- **Platform:** macOS 14+, Apple silicon, native Swift, as today.
- **Privacy:** nothing leaves the Mac (ADR 0007).
- **Reuse:** the current scanner and cleanup service, their tests and the Cleanup view.
- **Maintenance:** the author alone, with no budget. Third-party tools (`simctl`, `dotnet`, `docker`) can change their output with an Xcode or Docker update, so reading them must be defensive (ADR 0005).
- **Time:** the author has 3 to 4 days a week at the moment. The Must scope is capped at 14 working days, about 4 weeks (Kill criteria 3). It was 10 before Android was added. The target is a 1.1 release, with no fixed date.
- **Decision to record before coding:** ADR 0006 describes deleting files inside the home folder. Removing a simulator or cleaning Docker through a tool is a different kind of action, so a new ADR must complete ADR 0006 (supersede only what it changes).
- **Preference, not a decision:** call the tools by their commands. The architecture is decided in `ARCHITECTURE.md`.

## Prior art

Many Mac cleaners for developers exist: [ClearDisk](https://github.com/bysiber/cleardisk) (SwiftUI menu bar app: Xcode, node_modules, CocoaPods, SwiftPM, Docker, pip, Cargo), [TidyDisk](https://github.com/prateekcode/tidydisk), [BlitzClean](https://www.opensourcealternatives.to/item/blitzclean) (simulators, Docker layers, node_modules), [Harbofly](https://www.producthunt.com/p/harbofly-understand-your-storage/harbofly), [DevCleaner for Xcode](https://christiantietze.de/posts/tags/devtools/) and [DevCleaner](https://peerlist.io/dawedev/project/devcleaner--reclaim-gbs-from-mac-dev-tools). The search results (2026-11-15, quick check, not a full survey) do not say whether any of them handles NuGet. The author tried none of them.

What Soaro adds is small: the cleanup lives inside a monitor that is already installed, sends nothing and warns before the disk is full. The case for building it is the author's own need and interest, and that is accepted. A deeper survey with a build-or-adopt verdict can be done with the `prior-art` skill if wanted.

## Risks and assumptions

| # | Assumption or risk | Impact if false | Status |
| --- | --- | --- | --- |
| A1 | **Riskiest (Must):** Soaro can show which simulators are disposable clearly enough for the author to dare delete them. | The feature is dangerous or never used. | Partly tested (Test A): 83 % of the space is idle for more than 60 days (29 % at 90 days); 23 % is superseded duplicates; "no app of yours" is useless as a signal (14 devices carry the author's own app). The 5-device check by the author was done on 2026-11-17: confirmed (60 days stays the default). |
| A2 | **Riskiest (Should):** a Docker cleanup started from Soaro returns real space to the Mac, without touching volumes. | Docker support has no value. | Untested (Test B) |
| A3 | Removing a simulator in the supported way needs no administrator rights. | Needs a privileged step, which the app avoids. | Untested |
| A4 | Other developers want this and can ignore it if not. | Low: costs only space in the view. | Untested; low impact |
| A5 | The output of `simctl`, `dotnet`, `docker` and the Android tools stays readable across Xcode, Docker and Android updates. | Cleaner hidden or broken after an update. | Mitigated by R6 |
| A6 | An Android virtual device can be told apart as disposable well enough. The only signal found is a file date (no "last used" field as with `simctl`), and the five small AVD all show the same date, 2026-10-23. | Weak suggestions; the author decides by hand. | Partly tested: Pixel_9a (11 GB) was last written 2026-09-22, 54 days ago, so it is not suggested at the 60-day default. SL10: signal proposed (newest date among the emulator-written files listed in `ARCHITECTURE.md`), pending the author; on the SL10 read-only scan of the author's Mac, the six AVDs gave dates 0 to 6 days old, all from `emulator-user.ini` |
| A7 | Soaro can tell that an emulator is running. | A running device could be removed. | Untested; covered by R17 tests |
| R-1 | ADR 0006 does not cover non-file actions. | Unsafe or inconsistent rules. | Open; fixed by a new ADR before coding |

## Cheapest test

- **Test A (simulators), done 2026-11-15, read-only, on the author's Mac.** Criterion: at least 80 % of the space gets a readable reason. Result: met at a 60-day threshold (83 %), not at 90 days (29 %), so the threshold stays adjustable with 60 as default. The check on a sample of 5 devices by the author was done on 2026-11-17: confirmed.
- **Test A2 (Android), done 2026-11-15, read-only.** Sizes and dates measured (see Problem and A6). Result: the size signal is strong (Pixel_9a alone is 11 GB); the "last used" signal is weak and should be checked against Android Studio on the author's Mac (R16).
- **Test B (Docker), to do, about one evening.** With Docker Desktop running, measure `df` and the disk image size before and after a build-cache prune and an unused-image prune (no volumes), with and without Docker's own space-reclaim command. Criterion: at least half of what Docker says it freed comes back on the Mac. OrbStack cannot be tested (not installed).

## Kill criteria

1. **Docker:** if Test B shows less than half of the announced space coming back, drop Docker (R10, R11). The rest continues.
2. **Safety:** one confirmed case of data lost because of Soaro removes the feature from the published version until its design is reviewed.
3. **Overrun:** if the Must scope (R1 to R9 and R16 to R18) is not finished after 14 working days, stop and cut the scope to iOS simulators and Android virtual devices only (R3 to R5, R16, R17, with R6 to R9 and R18).
4. **Use:** if 2 months after the release the author has not used it at least once a month, mark it as low value and stop extending it.

## Open questions

- **Simulator runtimes (31.5 GB, outside the home folder):** include them? They are bigger than the devices once cleaned. It would need the "home folder only" rule of ADR 0006 to change. Not decided; the non-goal stands until the author decides.
- **Default threshold:** is 60 days right? Answered on 2026-11-17: the author's 5-device check confirmed 60 days (factual note; no requirement changed). Note that at 60 days the biggest Android device (Pixel_9a, 54 days) is not suggested; whether that is acceptable is for the author to say.
- **Android last-used date:** which file date is the best signal (userdata image, snapshots, or the emulator's own records)? Signal proposed in SL10 (newest date among the emulator-written files listed in ARCHITECTURE), pending the author.
- **Where it lives in the interface:** the developer caches section, or a tool of its own like the simulator list. For the `ux` skill.
- **Docker tool location:** Docker Desktop and OrbStack install their command in different places; to settle in the architecture.
- **Quick clean:** the default (R13) is "excluded"; confirm.

## Decision log

| Date | Decision or override | Reason |
| --- | --- | --- |
| 2026-11-15 | Spec created from the interview. Feature is an extension of Soaro, not a new app. | Existing scanner and cleanup view |
| 2026-11-15 | Docker is Should, behind Test B. | NuGet and simulators already reach the 30 GB goal; Docker is the riskiest and least certain |
| 2026-11-15 | Motivation accepted as personal need and pleasure, not market demand. | Author's answer; existing tools cover much of it |
| 2026-11-15 | Simulator threshold adjustable, default 60 days. | Test A: 83 % classified at 60 days, 29 % at 90 |
| 2026-11-15 | Simulator runtimes left as a non-goal for now, listed as an open question. | Outside the home folder; the author has not decided |
| 2026-11-15 | Android added (version 0.2): virtual devices Must (R16 to R18), system images Should (R19). | Author's request; measured 34 GB on his Mac, all inside the home folder. Same need and mechanism as iOS simulators; images are Should because removing one means a multi-GB download to recreate a device |
| 2026-11-15 | R8 extended (no ID change): the default button of a confirmation is Cancel, for all confirmations, new and existing. | Author's decision during the UI step: today the first button, which deletes, is the default, so Return deletes |
| 2026-11-15 | R2 marked "Covered by existing" (version 0.3); the SwiftPM cache is not a separate cleaner. | Architecture review: `CleanupService.items` already deletes everything in `~/Library/Caches` except `com.apple.*`; the cache is 52 KB on the author's Mac; the neighbouring folder holds configuration |
| 2026-11-15 | R17 reworded (no ID change): "removed with its registration" instead of "in the way the Android tools support". | ADR 0009: `avdmanager` needs Java, which an app started from the Finder does not have; the AVD is removed as its `.ini` and `.avd` pair |
| 2026-11-15 | R10 reworded (no ID change): untagged images pre-selected, other unused images listed but not pre-selected. Soaro never runs Docker's reclaim container. | ADR 0010: deleting a tagged image means downloading it again; the reclaim container pulls an image and runs privileged, against R9 |
| 2026-11-15 | Must budget raised from 10 to 14 working days; fallback is iOS simulators plus Android devices. | The Must scope grew by one kind of target; keeping 10 would make the overrun criterion almost certain |
