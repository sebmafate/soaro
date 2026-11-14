#!/bin/bash
# Builds a release: signed app, signed DMG, optional notarization, Sparkle appcast.
#
# Usage: scripts/release.sh [--notarize]
#
# Without --notarize nothing is sent to Apple: you get a signed DMG you can inspect.
# With --notarize the DMG is submitted to the notary service, then stapled. This needs the keychain
# profile created once with:  xcrun notarytool store-credentials "soaro-notary" ...
# The full procedure is in docs/releasing.md.
set -euo pipefail

cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Sebastien Ferrand (K8H46QQHGX)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-soaro-notary}"
REPO="sebmafate/soaro"
VERSION="$(tr -d '[:space:]' < VERSION)"
OUT="build/release"
DMG="$OUT/Soaro-$VERSION.dmg"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

NOTARIZE=0
[ "${1:-}" = "--notarize" ] && NOTARIZE=1

echo "== 1/4 Build and sign the app"
SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh

echo "== 2/4 Create the DMG"
rm -rf "$OUT/stage" "$DMG"
mkdir -p "$OUT/stage"
cp -R build/Soaro.app "$OUT/stage/"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -volname "Soaro" -srcfolder "$OUT/stage" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$OUT/stage"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "Created $DMG"

if [ "$NOTARIZE" = 1 ]; then
  echo "== 3/4 Notarize (sent to Apple) and staple"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
else
  echo "== 3/4 Notarization skipped (use --notarize)"
fi

echo "== 4/4 Sparkle appcast"
# generate_appcast reads the EdDSA private key from the keychain and signs each archive found in the folder.
# Updates are downloaded from the GitHub release of the same version.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  -o "$OUT/appcast.xml" "$OUT"
echo "Created $OUT/appcast.xml"
shasum -a 256 "$DMG"
