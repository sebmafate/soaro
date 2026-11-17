# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and the versions follow [semantic versioning](https://semver.org).

## [Unreleased]

### Added

- New tool “Simulators and emulators” (Cleanup > Tools): lists your Xcode simulators with their real size, pre-selects those inactive for more than 60 days and older copies, and removes the ones you choose the way Xcode does, after a confirmation that names them. A running simulator is never removed.
- The same tool also lists your Android virtual devices with their real size, system and last-use estimate, and shows how long each has been inactive. Check the ones you want and press Delete: each one is removed with its registration, after the same confirmation, in one batch with any simulators you checked. A running emulator is never removed. Android devices are not pre-selected for now, and without an Android SDK nothing Android appears.
- A “Select all” checkbox in the header of every list where you tick items (simulators, Android emulators, large files, inactive projects, an app's related files): it checks or unchecks every item of that section, shows a dash when only some are ticked, and never ticks a running simulator or emulator.
- New cleaner “NuGet packages” (Cleanup > Developer): frees the NuGet package cache, after a confirmation. It is not part of the quick clean.

### Changed

- In every confirmation window, Cancel is now the default button: pressing Return no longer deletes or removes anything.
- VoiceOver now reads the name of the item on the selection buttons in Inactive projects, Large files and Uninstaller, and each row is read as one item; “Show in Finder” is offered as an action of the row.
- The Delete and Uninstall buttons use a deeper red with better contrast.
- Messages shown at the bottom of the window and the menu bar panel now fade in without sliding when Reduce Motion is on, and VoiceOver reads them aloud when they appear.

### Fixed

- The scroll bar of the Cleanup and Settings pages now sits at the right edge of the window; the explanation under the simulators list is no longer cut off.
- In demo mode (`SOARO_DEMO=1`), confirming in the Cleanup rows, Large files, Inactive projects, the Uninstaller and Startup items no longer deletes, trashes or removes real files or changes real login items, and the Quit buttons no longer quit real apps.
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
