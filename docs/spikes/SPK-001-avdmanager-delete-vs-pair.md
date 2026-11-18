# SPK-001: Does `avdmanager delete avd` remove more than the `.ini` and `.avd` pair?

| | |
| --- | --- |
| Status | done |
| Date | 2026-11-18 |
| Time box | 1 hour (agent run on the author's Mac; stop and record at the limit) |
| Serves | R17, ADR 0009 (route by supported means), `ARCHITECTURE.md` risk 5, SL11 (direct route built), SL12b (open decision: direct deletion or `sdkmanager`) |
| Verdict | **confirmed**: same result, `avdmanager delete avd` removes nothing more than the pair |

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

Run on 2026-11-18 between 08:33 and 08:40 on the author's Mac, about 7 minutes of work plus 5 listings of about 50 s each. Throwaway script in the session scratchpad (not committed). Listings: 467 paths in the baseline `B0` (0 text references to the name).

| Step | Observed |
| --- | --- |
| Create (`avdmanager create avd -n Soaro_Test_AVD -k system-images;android-34;default;arm64-v8a -d pixel`) | `Soaro_Test_AVD.ini` (134 bytes) and `Soaro_Test_AVD.avd` created, 4 entries at first |
| Boot headless, port 5582 | `sys.boot_completed` after about 25 s (run 1) and 20 s (run 2); clean stop with `adb emu kill` in 6 s; quickboot snapshot `default_boot` saved |
| State before removal, both runs | **Identical**: 506 paths, 6 text references; the `.avd` folder holds 36 paths (images and qcow2 overlays, `config.ini`, `hardware-qemu.ini`, `emulator-user.ini`, locks, `snapshots/default_boot/*`, `modem_simulator/*`) |
| Only path outside the pair created by the boot | `~/.android/modem-nv-ram-5582`: named after the emulator port, not after the AVD, shared by every AVD started on that port; neither route removes it |
| Text references to the name (outside the pair): | none besides the 6 inside the `.avd` folder and the `.ini` file |
| **Route 1, `avdmanager delete avd -n Soaro_Test_AVD`** | "AVD 'Soaro_Test_AVD' deleted."; 38 paths gone (the whole `.avd` folder, 36 paths, and the `.ini`); state after = baseline + `modem-nv-ram-5582`; 0 text references |
| **Route 2, `rm -rf` the `.avd` folder then `rm` the `.ini`** (the SL11 order) | state after = baseline + `modem-nv-ram-5582`; 0 text references |
| Compare the two states after removal | **Identical** file lists and identical (empty) reference lists |

Checks that the author's data was left alone: the six AVDs (`Pixel_9a`, `ap26`, `ap30`, `ap31`, `ap33`, `ap34`) are all still listed by `avdmanager list avd` afterwards and `ap34`, running on port 5554 throughout, was never stopped. After the spike, the spike's own `modem-nv-ram-5582` file was removed by hand (it was not in the baseline).

Surprises and side findings:

- A real emulator was already running on the author's Mac (`ap34`). Its process line, user name replaced by `test`: `/Users/test/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd ap34 -port 5554 -no-snapshot -no-audio -no-boot-anim`. This is the real format the detection of risk 6 reads (`-avd <name>`); the spike did not test the detection itself.
- The emulator boots from the command line in about 25 s on this Mac, which makes this kind of check cheap to repeat.

## Verdict

**Confirmed.** For a disposable AVD created with the command line and booted once (quickboot snapshot included), `avdmanager delete avd` removes exactly what the pair route removes: the `.avd` folder and the `.ini`. Nothing else is deleted or edited by name, and the two final states are identical. Risk 5 is closed for this case.

What remains unknown (limits of the spike):

- The comparison lists names and searches content for the AVD's name; a file that `avdmanager` edits **without naming the AVD** (for example a registry or cache of the tool) would not show. No such file was seen to appear or disappear, but modification dates and contents of unrelated files were not compared.
- The AVD was created and booted from the command line, not from Android Studio, which might leave its own caches; Android Studio was not running and its folders showed no change.
- An AVD located outside `~/.android/avd` (a `path=` elsewhere) was not tested; SL11 refuses those anyway.
- Soaro's own removal code was not run (the pair route was done with `rm`): the SL11 checks of the author cover it, and whether the part of step 2 about Soaro's toast and `df -k ~` was done is the author's to say.
- This is about AVDs only. It says nothing about the removal route of **system images** in SL12b (direct deletion or `sdkmanager`), which is a separate decision.

## Consequences

- ADR: none changes. ADR 0009's choice for AVD removal (plain deletion of the pair, the same result as the tool's own route) is confirmed by evidence.
- Architecture: risk 5 in `ARCHITECTURE.md` moves from open to closed (2026-11-18), with a change-log row.
- Spec or kill criteria: none touched (R17 holds).
- Plan: SL12b loses its first gate (the SL11 checks and the risk 5 result); its decisions remain (route for system images, pre-selection, wrong "not used"). `STATUS.md` next action updated.
