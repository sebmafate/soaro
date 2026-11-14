#!/bin/bash
# Captures the standalone window of Soaro in demo mode (made-up data, nothing personal) for the website.
#
# Usage: scripts/make-screenshots.sh <output-folder> [language ...]
# Example: scripts/make-screenshots.sh site/screenshots en fr
#
# It launches build/Soaro.app (run scripts/build-app.sh first) once per section and language.
# The window follows the current appearance of the Mac (light or dark).
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:?output folder}"; shift || true
LANGS=("$@"); [ ${#LANGS[@]} -gt 0 ] || LANGS=(en fr)
SECTIONS=(overview performance battery network history cleanup machine settings
          cleanup:largeFiles cleanup:devProjects cleanup:uninstaller cleanup:startup)
EXE="build/Soaro.app/Contents/MacOS/Soaro"
[ -x "$EXE" ] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"      # absolute path: the app is started from another folder

for lang in "${LANGS[@]}"; do
  case "$lang" in
    en) locale="en_US" ;; fr) locale="fr_FR" ;; de) locale="de_DE" ;; es) locale="es_ES" ;; it) locale="it_IT" ;;
    pt-BR) locale="pt_BR" ;; ja) locale="ja_JP" ;; zh-Hans) locale="zh_CN" ;; ko) locale="ko_KR" ;; *) locale="${lang//-/_}" ;;
  esac
  for section in "${SECTIONS[@]}"; do
    file="$OUT/${lang}-${section//:/-}.png"
    rm -f "$file"
    pkill -x Soaro 2>/dev/null || true; sleep 1
    SOARO_DEMO=1 SOARO_SECTION="$section" SOARO_CAPTURE="$file" \
      "$EXE" -AppleLanguages "($lang)" -AppleLocale "$locale" >/dev/null 2>&1 &
    pid=$!
    sleep 3
    open build/Soaro.app                      # relaunching an app that is running opens its window
    for _ in $(seq 1 20); do [ -f "$file" ] && break; sleep 1; done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    [ -f "$file" ] && echo "$file" || echo "MISSING $file" >&2
  done
done

# The website uses WebP (about 5 times lighter than PNG): the full size (2x) and a 946 px wide version for srcset.
if command -v cwebp >/dev/null; then
  for png in "$OUT"/*.png; do
    cwebp -quiet -q 90 -alpha_q 100 "$png" -o "${png%.png}.webp"
    cwebp -quiet -q 88 -resize 946 0 "$png" -o "${png%.png}-946.webp"
    rm "$png"
  done
fi
