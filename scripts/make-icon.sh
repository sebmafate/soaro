#!/bin/bash
# Génère build/AppIcon.icns depuis assets/icon.svg (rendu avec transparence + iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Le renderer est compilé une fois puis réutilisé pour chaque taille (10 rendus nets, sans redimensionnement).
swiftc -O scripts/render-svg.swift -o "$TMP/render-svg"

SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
  "$TMP/render-svg" assets/icon.svg "$SET/icon_${size}x${size}.png" "$size"
  "$TMP/render-svg" assets/icon.svg "$SET/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$SET" -o build/AppIcon.icns
echo "✓ build/AppIcon.icns"
