# SPK-001: Does `avdmanager delete avd` remove more than the `.ini` and `.avd` pair?

| | |
| --- | --- |
| Status | running |
| Date | 2026-11-18 |
| Time box | 1 hour (agent run on the author's Mac; stop and record at the limit) |
| Serves | R17, ADR 0009 (route by supported means), `ARCHITECTURE.md` risk 5, SL11 (direct route built), SL12b (open decision: direct deletion or `sdkmanager`) |
| Verdict | (to fill when done) |

## Question

After a disposable Android virtual device that has booted once is removed as its pair (the `.avd` folder, then the `.ini` file: the route SL11 built), does anything remain that `avdmanager delete avd -n <name>` would have removed?

## Why it matters

- **Same result:** the direct route of SL11 is confirmed, risk 5 is closed, and SL12b can keep the same kind of route (it still has its own decisions to take).
- **`avdmanager` removes more:** the direct route leaves residue, so `/trellis:change-course` on the Android removal route (ADR 0009 says to prefer the supported route of the tool when the tool owns the state).

## Criteria (written before running)

The comparison is two runs on one disposable AVD named `Soaro_Test_AVD`, created the same way each time, booted once, then removed by one route per run. Before the first run, a baseline lists the candidate places; after each removal the same listing is taken again.

- **Success (same result, risk 5 closed):** after each route, the paths and text files that refer to `Soaro_Test_AVD` (by path or by content, images excluded) are the same, and the difference between the baseline and the state after removal is the same for both routes, ignoring paths that do not name the AVD and are the same for both runs (for example a `modem-nv-ram-<port>` file named after the emulator port, which is not specific to the AVD). In particular `avdmanager` deletes no path and edits no file that the pair route leaves.
- **Failure (`avdmanager` removes more):** at least one path (file or folder) or one text reference to `Soaro_Test_AVD` is removed or changed by `avdmanager delete avd` and still present after the pair route.
- **Inconclusive:** the AVD cannot be created or cannot boot, so the "booted once" state is not reached; or the two runs cannot be made comparable (for example the first route leaves state that changes the second); or a place that may hold residue could not be listed. The verdict then states what stays unknown.
- **Conditions:**
  - Tools: the author's Android SDK (`~/Library/Android/sdk`, `avdmanager` in `cmdline-tools/latest`, `emulator`), Java 21 (Homebrew), macOS 27 on Apple silicon.
  - System image: an already installed one (`system-images;android-34;default;arm64-v8a`), no download; hardware profile `pixel`.
  - **Created and booted from the command line** (`avdmanager create avd`, then `emulator -avd Soaro_Test_AVD -no-window -no-audio` on its own port), **not from Android Studio** as the SL11 checklist said. Android Studio is not running. Difference to keep in mind: Android Studio's own caches are not exercised by a command-line boot.
  - The pair route is done by hand with `rm` on the two exact paths, in the order of SL11 (folder, then `.ini`); Soaro's own code is not run (it has no command-line entry), so this tests what the route leaves, not Soaro's code.
  - **Never touched:** the six AVDs of the author (`Pixel_9a`, `ap26`, `ap30`, `ap31`, `ap33`, `ap34`). One of them (`ap34`, port 5554) is running at the start of the spike; the spike uses another port and does not stop it.
  - Places listed: `~/.android` (names; the content of the six other `.avd` folders is skipped), `~/Library/Android/sdk` (depth 3, `system-images`, `emulator`, `platforms`, `build-tools`, `sources` and `platform-tools` skipped), `~/Library/Application Support/Google/AndroidStudio*`, `~/Library/Caches/Google`, `~/Library/Logs/Google`, `~/Library/Preferences` (Android-related files), `~/.emulator_console_auth_token`, `/tmp/android-<user>`. Text search for the name with `grep -rIl` (binary and `*.img`, `*.qcow2` excluded) over the same places.

## Experiment

A throwaway shell script outside the repository (the scratchpad of the session), not committed. Per route: create the AVD, boot it headless until `sys.boot_completed`, shut it down cleanly (`adb emu kill`), list, remove, list again. Observed outputs are copied into "Result" below.

## Result

(to fill)

## Verdict

(to fill)

## Consequences

- ADR: (to fill)
- Architecture: risk 5 in `ARCHITECTURE.md` (to fill)
- Spec or kill criteria: (to fill)
- Plan: SL12b open decision, route (to fill)
