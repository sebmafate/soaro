# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and the versions follow [semantic versioning](https://semver.org).

## [Unreleased]

### Added

- Settings > About now links to the website, soaro.app, next to the app logo (the French page when Soaro runs in French).
- With “Show public IP and country” on and the network rates in the menu bar, the flag of your public IP's country now shows to the right of the rates (and its name in the tooltip); the flag stays up to date (it follows a VPN or network change within seconds, which means Soaro asks the lookup service about every 5 minutes while the flag shows, not only when the Network tab is open), and it shows nothing when the country is unknown.
- A button in the toolbar of the window (the sidebar icon, with a tooltip and a VoiceOver label “Toggle Sidebar”) collapses and reopens the sidebar. The sidebar is open each time the window opens (SL20).

### Changed

- Window (experiment, to be confirmed): the main area now has an opaque background so the content is easier to read, while the sidebar stays translucent; the cards in the window use a soft flat fill instead of glass. The menu bar panel is unchanged.
- In Settings, the colour thresholds (processor and GPU load, disk, battery) are set on one track with three draggable handles instead of three steppers, and in finer steps: 1 point instead of 5, with the thresholds allowed to sit 1 point apart. The coloured bands follow the handles as you drag, each handle shows its value on a label joined to it by a thin line, and a small mark shows the current value of that measure. Your saved thresholds are kept. Each handle can also be moved with the arrow keys (Shift for 5, Home and End for the limits) and with VoiceOver (increment and decrement). (SL17)

### Changed

- The battery in the menu bar is now an icon like the macOS one, followed by the percentage on the same line (the “BAT” label is gone): the fill follows the real level, a lightning bolt shows while the Mac is charging, and the fill turns orange, red or scarlet with your thresholds, like the percentage. The Battery card and the Battery tab show the same icon. A small plug replaces the bolt while the Mac is plugged in but not charging (full, or charge held by a limit), and the battery bar on the card and the tab now turns orange, red or scarlet at your own thresholds.

## [1.1.0] - 2026-11-18

### Added

- New tool “Simulators and emulators” (Cleanup > Tools): lists your Xcode simulators with their real size, pre-selects those inactive for more than 60 days and older copies, and removes the ones you choose the way Xcode does, after a confirmation that names them. A running simulator is never removed.
- The same tool also lists your Android virtual devices with their real size, system and last-use estimate, and shows how long each has been inactive. Check the ones you want and press Delete: each one is removed with its registration, after the same confirmation, in one batch with any simulators you checked. A running emulator is never removed. Without an Android SDK nothing Android appears.
- Android emulators not used for more than 60 days, judged by the files the emulator writes while a device runs, are now pre-selected like simulators.
- The same tool also lists the Android system images installed in your Android SDK, with their size and the virtual devices that use them, or says when it cannot tell. They are shown for information only: nothing is removed.
- A “Select all” checkbox in the header of every list where you tick items (simulators, Android emulators, large files, inactive projects, an app's related files): it checks or unchecks every item of that section, shows a dash when only some are ticked, and never ticks a running simulator or emulator.
- New tool “Docker” (Cleanup > Tools, shown when Docker is installed): shows what Docker uses (build cache, untagged images, containers, volumes), pre-selects the build cache and the untagged images, and cleans them after a confirmation that warns the next build will be slower. A minute later it tells you how much space really came back on your Mac, and says so when Docker's disk image did not give it back. Containers, volumes and images with a tag are never touched, and Docker is never started by Soaro. Soaro only cleans Docker on this Mac: if Docker points at a remote engine or a shared builder, the tool says so and does nothing, and the confirmation names the engine.
- New cleaner “NuGet packages” (Cleanup > Developer): frees the NuGet package cache, after a confirmation. It is not part of the quick clean.

### Changed

- In every confirmation window, Cancel is now the default button: pressing Return no longer deletes or removes anything.
- VoiceOver now reads the name of the item on the selection buttons in Inactive projects, Large files and Uninstaller, and each row is read as one item; “Show in Finder” is offered as an action of the row.
- The Delete and Uninstall buttons use a deeper red with better contrast.
- Messages shown at the bottom of the window and the menu bar panel now fade in without sliding when Reduce Motion is on, and VoiceOver reads them aloud when they appear.
- Supporting text (details, sizes, notes and section headers) uses a slightly darker grey that is easier to read, in light and dark mode and with Increase Contrast; section headers are one step larger.

### Fixed

- The scroll bar of the Cleanup and Settings pages now sits at the right edge of the window; the explanation under the simulators list is no longer cut off.
- In demo mode (`SOARO_DEMO=1`), confirming in the Cleanup rows, Large files, Inactive projects, the Uninstaller and Startup items no longer deletes, trashes or removes real files or changes real login items, and the Quit buttons no longer quit real apps.
- In demo mode (`SOARO_DEMO=1`), the “Open at login” switch in Settings no longer adds or removes the real login item of Soaro: it only changes on screen.
- French: the battery explanation no longer shows "100 %%".

## [1.0.1] - 2026-11-15

### Fixed

- The release built on GitHub had no Liquid Glass and no translations (the build machine used an old Xcode). It is now built with Xcode 26, and the build fails if translations are missing.

## [1.0.0] - 2026-11-15

First public version: monitoring of CPU, GPU, memory, disk, network and battery, 30-day history, recommendations and tips, cleanup tools, menu bar panel and standalone window.

### Added

- The app is translated into French, German, Spanish, Italian, Brazilian Portuguese, Japanese, Simplified Chinese and Korean, in addition to English.
- Automatic updates with Sparkle, and a "Check for updates..." button in the settings.
- Signed and notarized DMG for download.
- Open source release under the GPL-3.0, with documentation.

### Changed

- The app is now named **Soaro** (it was "Accalmie", and "MyCleaner" before). The identifier is `app.soaro`. History and preferences are imported automatically.
- Numbers, sizes, rates and durations follow the language and region of the Mac.
- `Soaro --diagnostics` prints in English.
