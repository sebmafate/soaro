# 0009. Cleanup actions that are not plain deletion: the supported route per target, under one contract

| | |
| --- | --- |
| Status | accepted |
| Date | 2026-11-15 |
| Supersedes | none. Completes [0006](0006-cleanup-safety-model.md), which stays accepted; this ADR answers its open point "the model for non-file targets" |
| Drives from | R3, R4, R5, R6, R7, R8, R9, R16, R17, R18; drivers: safety of deletion, honesty about fragile data, testable without the real tool |

## Context

ADR 0006 covers deleting files inside the home folder. The developer cleanup (`SPEC.md`) adds targets that are not simply folders to wipe: iOS simulator devices (owned by the CoreSimulator service), Android virtual devices (AVD), and later Docker. Measured on the author's Mac on 2026-11-15:

- `xcrun simctl delete <udid>` is the supported way to remove a simulator. Deleting its folder by hand leaves the device set inconsistent. `/usr/bin/xcrun` is always there.
- An AVD is a pair: `<name>.ini` and a `<name>.avd` folder. The folder holds a `multiinstance.lock` file even when no emulator runs, so that file does not prove an emulator is running. `avdmanager` works from the author's terminal only because Java is in its PATH (Homebrew OpenJDK). An app started from the Finder has no such PATH.
- The Android command-line tools are not in the author's PATH. They sit in `~/Library/Android/sdk/cmdline-tools/latest/bin`.
- The app has four copies of a small function that runs an external program (`Advice.run`, `CleanupService.emptyTrash`, `MachineInfo`, `SystemSampler`). None has a time limit. `docker`, `simctl` and Android tools can hang.
- ADR 0001 keeps Sparkle as the only dependency.

## Options considered

### Option A: everything is file deletion (extend ADR 0006)

- For: no external tool, simplest to test, nothing to find or run.
- Against: removing a simulator by hand leaves CoreSimulator inconsistent. This breaks R4. Not acceptable for simulators.

### Option B: always the vendor's tool (`simctl`, `avdmanager`, `docker`)

- For: the owner of the state does the removal.
- Against: `avdmanager` needs Java, which a Finder-launched app does not have, so Android would silently disappear for many users (R6) or break. More exposed to output changes.

### Option C: the supported route per target, under one contract (chosen)

- For: the vendor's tool where a system service owns the state (`simctl`, Docker); the documented file layout where the format is plain files (AVD pair, NuGet, SwiftPM). One set of rules for all, so safety does not depend on which route is used.
- Against: two kinds of route to maintain and explain. The AVD route relies on `avdmanager delete` doing what we think (see Open points).

## Decision

We chose **Option C**, with this contract for every new cleaner:

1. **Scope:** only targets inside the home folder, as in ADR 0006. Simulator runtimes (outside the home folder) stay out of scope.
2. **Confirmation:** each action is confirmed first, naming the target, its size and what is lost (R8).
3. **Never on a running target:** a simulator in state `Booted`; an AVD whose name appears as `-avd <name>` in a running process command line; for Docker, the rules of ADR 0010.
4. **Finding tools:** absolute paths from a list of candidates, never the PATH and never a shell. `/usr/bin/xcrun` for simulators. For Android, `ANDROID_SDK_ROOT` or `ANDROID_HOME` when visible to the app, then `~/Library/Android/sdk` (R18). A tool not found hides the cleaner (R6).
5. **One command runner**, written in the app (no new dependency): a protocol with a real implementation based on `Process`, a time limit that kills the process, bounded output, and a fake for tests. Only new code uses it; the four existing copies stay as they are for now.
6. **AVD removal:** delete the `.ini` and the `.avd` folder together. If the `.ini` points to a custom path, that path must also pass `isSafeToDelete`, otherwise the action is refused.
7. **After the action:** rescan, and report the space really freed, not the announced size (R7).
8. **On failure:** stop for that target and show the error. There is **no fallback to deleting files** for a target owned by a tool (no `rm` when `simctl` fails).

## Consequences

- Good: safe removal of simulators; Android works without Java; every test runs with a fake runner and recorded outputs.
- Bad: one more internal component (the runner) and a list of tool locations to maintain; two routes to document.
- Risks and how we will notice them: an Xcode or Android update changes the output or the layout; the cleaner hides itself (R6) and the author notices that it is missing, so each cleaner needs a test on a recorded real output (the testing decision). An AVD pair deleted without `avdmanager` could miss something it cleans up: checked once by hand (Open points).

## Revisit when

- `avdmanager delete` is found to remove more than the pair (re-open the AVD route).
- A cleaner needs an action outside the home folder (for example simulator runtimes): this ADR and ADR 0006 are reopened together.
- The four existing runner copies cause a bug: move them to the shared runner.

## Open points

- To verify in the first Android task: create a disposable AVD, remove it with `avdmanager` and by the pair route, and compare what is left on disk.
- Detecting a running AVD from the process list is untested with a real running emulator.
- The time limit value (proposal: 30 seconds, longer for `simctl list` on a cold start) is set during implementation.
- Docker is decided in ADR 0010, after the spike (Test B of the spec).
