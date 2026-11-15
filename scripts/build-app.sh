#!/bin/bash
# Builds Soaro.app (menu bar app, no Dock icon) in ./build.
#
# Usage: scripts/build-app.sh [--install]
#   --install   also copies the app to /Applications
#
# Signing is controlled by the SIGN_IDENTITY environment variable:
#   (unset)                                   ad-hoc signature, good enough to run on this Mac
#   "Developer ID Application: Name (TEAM)"   release signature (hardened runtime + secure timestamp)
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Soaro.app"
BUNDLE_ID="app.soaro"        # soaro.app, reversed
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
FEED_URL="https://soaro.app/appcast.xml"
# Public half of the Sparkle EdDSA key (the private half lives in the maintainer's keychain, see docs/updates.md).
SPARKLE_PUBLIC_KEY="xr3e5chR/I9MFaxbIraroXbH5gMxnyXCWpMe3ndYMEU="
IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Soaro"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Soaro"

# Sparkle: the framework must sit in Contents/Frameworks, and the executable must know where to find it.
SPARKLE_FRAMEWORK="$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)"
[ -n "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle.framework not found: run 'swift build' first" >&2; exit 1; }
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Soaro"

# Translations: the String Catalogs are compiled into <language>.lproj folders (Localizable.strings, InfoPlist.strings)
# at the root of the app resources, where macOS looks for them. SwiftPM only does this itself with the newest
# toolchain (it merely copies the catalogs with Xcode 26), so we call Xcode's own compiler, which gives the same
# result everywhere.
LPROJ_OUT="build/lproj"
rm -rf "$LPROJ_OUT"
mkdir -p "$LPROJ_OUT"
for catalog in Sources/Soaro/Resources/*.xcstrings; do
  xcrun xcstringstool compile "$catalog" --output-directory "$LPROJ_OUT"
done
LANGS="en"
for lproj in "$LPROJ_OUT"/*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$APP/Contents/Resources/"
  LANGS="$LANGS $(basename "$lproj" .lproj)"
done
# A release without translations is a bug (the String Catalogs were not compiled): stop.
if [ "$IDENTITY" != "-" ] && [ "$(echo "$LANGS" | tr ' ' '\n' | sort -u | wc -l)" -lt 2 ]; then
  echo "No translation was compiled (swift: $(swift --version 2>&1 | head -1)). Check xcrun xcstringstool." >&2
  exit 1
fi
LOCALIZATIONS_XML=""
for l in $(echo "$LANGS" | tr ' ' '\n' | sort -u); do LOCALIZATIONS_XML="$LOCALIZATIONS_XML<string>$l</string>"; done

# Icon (optional): generated from assets/icon.svg when possible.
if scripts/make-icon.sh >/dev/null 2>&1; then
  cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "Warning: icon not generated, the app will use the default icon"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>$LOCALIZATIONS_XML</array>
  <key>CFBundleName</key><string>Soaro</string>
  <key>CFBundleDisplayName</key><string>Soaro</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Soaro</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Sébastien Ferrand. GPL-3.0.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Soaro needs to control the Finder to empty the Trash.</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad hoc"
else
  # Inside-out: every nested component first, the app last. Hardened runtime and a secure timestamp are
  # required by the notary service.
  SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  "${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Updater.app"
  "${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
  "${SIGN[@]}" --entitlements scripts/Soaro.entitlements "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Signed with: $IDENTITY"
fi
echo "Built $APP (version $VERSION, build $BUILD)"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/Soaro.app
  cp -R "$APP" /Applications/Soaro.app
  echo "Installed in /Applications/Soaro.app"
fi
