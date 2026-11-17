# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and the versions follow [semantic versioning](https://semver.org).

## [Unreleased]

### Added

- New tool “Simulators and emulators” (Cleanup > Tools): lists your Xcode simulators with their real size and pre-selects those inactive for a long time and older copies. Removal comes in a later version.
- New cleaner “NuGet packages” (Cleanup > Developer): frees the NuGet package cache, after a confirmation. It is not part of the quick clean.

### Changed

- In every confirmation window, Cancel is now the default button: pressing Return no longer deletes or removes anything.
- VoiceOver now reads the name of the item on the selection buttons in Inactive projects, Large files and Uninstaller, and each row is read as one item; “Show in Finder” is offered as an action of the row.
- The Delete and Uninstall buttons use a deeper red with better contrast.

### Fixed

- In demo mode (`SOARO_DEMO=1`), confirming in the Cleanup rows, Large files, Inactive projects, the Uninstaller and Startup items no longer deletes, trashes or removes real files or changes real login items, and the Quit buttons no longer quit real apps.
- French: the battery explanation no longer shows "100 %%" (SL2; AI-assisted wording, to review by the author).

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
