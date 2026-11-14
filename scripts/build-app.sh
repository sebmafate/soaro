#!/bin/bash
# Construit Accalmie.app (app de barre de menus, sans icône Dock) dans ./build
# Usage : scripts/build-app.sh [--install]   (--install copie l'app dans /Applications)
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Accalmie.app"
BUNDLE_ID="local.accalmie"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Accalmie"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Accalmie"

# Icône (optionnelle) : générée depuis assets/icon.svg si possible
if scripts/make-icon.sh >/dev/null 2>&1; then
  cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "⚠︎ Icône non générée, l'app utilisera l'icône par défaut"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Accalmie</string>
  <key>CFBundleDisplayName</key><string>Accalmie</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Accalmie</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Accalmie a besoin de contrôler le Finder pour vider la corbeille.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "✓ $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/Accalmie.app
  cp -R "$APP" /Applications/Accalmie.app
  echo "✓ Installée dans /Applications/Accalmie.app"
fi
