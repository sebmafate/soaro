# Architecture

Soaro is a Swift package (Swift 6 tools, Swift 5 language mode, macOS 14+). The app is assembled by hand from the SwiftPM binary: see `scripts/build-app.sh`.

## Files

| File | Role |
| --- | --- |
| `SystemSampler.swift` | CPU (global and per core), memory, disk, uptime, process list (Mach, `sysctl`, `ps`) |
| `Samplers/IOKitSamplers.swift` | GPU, battery, disk I/O, SMART (IOKit) |
| `Samplers/NetworkSampler.swift` | Speeds, Wi-Fi, ping, `nettop` per app, energy per app (`top`), I/O per process |
| `Samplers/VPNDetector.swift`, `Samplers/PublicIPService.swift` | Local VPN detection. Public IP, country and flag (the reply is validated and never shown if it is not a real IP) |
| `Samplers/SensorSampler.swift` | Temperatures (HID), fans and power (SMC) |
| `HistoryStore.swift` | SQLite history, aggregation by time slices, 30-day retention |
| `LeakDetector.swift` | Memory leak detection (linear regression and thresholds) |
| `Advice.swift` | Settings tips: read-only collection (`pmset`, `tmutil`, preferences), pure analysis |
| `RecommendationEngine.swift` | Pure function: measurements in, recommendations out |
| `CleanupService.swift`, `Cleanup/*` | Caches, large files, inactive projects, uninstaller, login items |
| `Cleanup/CommandRunner.swift`, `Cleanup/RealCommandRunner.swift` | Protocol and real runner of external programs (absolute path, no shell, time limit, bounded output). The only new code that uses `Process` |
| `Cleanup/ToolLocator.swift` | Finds an external tool by absolute path (`/usr/bin/xcrun` for the simulators) |
| `Cleanup/SimulatorScanner.swift`, `Cleanup/DeviceSuggestions.swift`, `Cleanup/SimulatorReport.swift` | iOS simulators, read-only: reads `simctl list devices -j`, measures the allocated size of each device folder, suggests what to pre-select, formats the `--scan` section |
| `LegacyMigration.swift` | Imports data from the former names of the app (history, preferences) |
| `AppState.swift` | Timing (3 s; sensors and battery every 9 s when the panel is closed), history, actions, notifications |
| `DemoData.swift` | Demo mode (`SOARO_DEMO=1`): a made-up Mac for screenshots, see [website.md](website.md) |
| `Updater.swift` | Sparkle integration. It stays inactive in a development build (see [updates.md](updates.md)) |
| `Views/MainWindow.swift`, `MachineInfo.swift` | Standalone window (AppKit, created on demand, destroyed on close) and the "This Mac" screen |
| `Views/MenuBarWidgets.swift` | Compact menu bar label, drawn in a template image |
| `Views/` | Tabbed panel. Its content is removed from the SwiftUI hierarchy when the panel is hidden, so it costs nothing when idle |
| `Resources/Localizable.xcstrings`, `InfoPlist.xcstrings` | Translations (see [CONTRIBUTING.md](../CONTRIBUTING.md#translations)) |

## Design choices

- **Pure functions where possible.** Measurements go into `RecommendationEngine` and `Advice`, and come out as recommendations. They are easy to test without a real Mac.
- **Cheap when idle.** When the panel is hidden, its views are removed. Sampling slows down for sensors and battery.
- **Defensive sensors.** HID and SMC are not documented by Apple. Every read can fail, and a failed read hides the section instead of showing wrong data.
- **Locale-aware formatting.** `Format` takes an explicit `locale`, so tests give the same result on any Mac.

## Command-line tools

The app binary has a few read-only modes. None of them writes or deletes anything.

```bash
Soaro --diagnostics                 # print all measurements as text (output is in English)
Soaro --diagnostics --public-ip     # same, plus the public IP lookup (explicit)
Soaro --scan [--per-root]           # run the cleanup scanners (caches, large files, projects, iOS simulators, apps, startup) on your home folder, read-only
Soaro --advice                      # print the settings read and the tips that follow
Soaro --snapshot <folder> [--dark] [--tools] [--window]   # render each tab to PNG (fake history, in memory)
```

For development, these environment variables are available: `SOARO_DEMO=1` runs the app on made-up data, `SOARO_CAPTURE=<file.png>` saves a capture of the standalone window, `SOARO_SECTION` chooses what it shows (`overview`, `performance`, `battery`, `network`, `history`, `cleanup`, `machine`, `settings`, or a cleanup tool such as `cleanup:largeFiles`), `SOARO_SCROLL` scrolls it, and `SOARO_DEBUG` adds traces.

## Permissions asked by macOS

- **Finder** (automation), the first time you empty the Trash.
- **System Events** (automation), if you show the "Open at Login" list.
- **Documents, Downloads, etc.**, when large files are scanned.
- The size of the **Trash** can only be read with Full Disk Access. The Trash can still be emptied without it.
- The Wi-Fi name (SSID) stays hidden without location access. The rest of the Wi-Fi information works.
- "Open at login" only works if the app is in `/Applications`.

## Previous names

The app was called "MyCleaner", then "Accalmie", and had a temporary identifier `local.soaro` before the domain was bought. On first launch, `LegacyMigration` imports history and preferences from the newest to the oldest version, and never overwrites an existing value. The old preference files (`~/Library/Preferences/local.soaro.plist`, `local.accalmie.plist`, `com.mycleaner.app.plist`, `MyCleaner.plist`) can be deleted by hand.

The app identifier is `app.soaro` (the domain `soaro.app`, reversed). It is set by `BUNDLE_ID` in `scripts/build-app.sh`.
