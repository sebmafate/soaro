#!/bin/bash
# Builds a release: signed app, signed DMG, optional notarization, Sparkle appcast.
#
# Usage: scripts/release.sh [--notarize]
#
# Without --notarize nothing is sent to Apple: you get a signed DMG you can inspect.
# With --notarize the DMG is submitted to the notary service, then stapled. Credentials come from:
#   - APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID (environment: this is what GitHub Actions uses), or
#   - the keychain profile created once with:  xcrun notarytool store-credentials "soaro-notary" ...
# The Sparkle signing key comes from SPARKLE_PRIVATE_KEY (environment, CI) or from the login keychain.
# Optional: RELEASE_NOTES_FILE (Markdown) is embedded in the appcast as the release notes.
# The manual procedure is in docs/releasing.md, the automated one in docs/ci-release.md.
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

# Notary credentials: explicit (CI) or keychain profile (maintainer's Mac).
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  NOTARY_AUTH=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi

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
  xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
else
  echo "== 3/4 Notarization skipped (use --notarize)"
fi

echo "== 4/4 Sparkle appcast"
# generate_appcast signs each archive found in the folder with the EdDSA private key: read from the
# SPARKLE_PRIVATE_KEY variable when set (CI, passed on stdin so it never touches the disk), else from the keychain.
# Updates are downloaded from the GitHub release of the same version.
APPCAST_ARGS=(--download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" -o "$OUT/appcast.xml")
if [ -n "${RELEASE_NOTES_FILE:-}" ] && [ -f "$RELEASE_NOTES_FILE" ]; then
  # Same name as the archive, other extension: generate_appcast picks it up as the release notes.
  cp "$RELEASE_NOTES_FILE" "$OUT/Soaro-$VERSION.md"
  APPCAST_ARGS+=(--embed-release-notes)
fi
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${APPCAST_ARGS[@]}" "$OUT"
else
  "$SPARKLE_BIN/generate_appcast" "${APPCAST_ARGS[@]}" "$OUT"
fi
echo "Created $OUT/appcast.xml"
shasum -a 256 "$DMG"
