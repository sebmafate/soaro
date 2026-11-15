#!/bin/bash
# Prints the CHANGELOG.md section of one version (without its heading), for the GitHub release and the appcast.
#
# Usage: scripts/release-notes.sh 1.1.0
# Fails when the version has no section, so a release cannot go out with empty notes.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?usage: release-notes.sh <version>}"

NOTES="$(awk -v v="$VERSION" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md)"

if [ -z "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ]; then
  echo "No section [$VERSION] (or it is empty) in CHANGELOG.md" >&2
  exit 1
fi
printf '%s\n' "$NOTES"
