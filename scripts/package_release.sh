#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
APP="$PROJECT_ROOT/Prompt Version Manager.app"
STAGING_ROOT="${TMPDIR:-/tmp}/prompt-version-manager-build"
STAGED_APP="$STAGING_ROOT/Prompt Version Manager.app"
DIST="$PROJECT_ROOT/dist"
ARCHIVE="$DIST/Prompt-Version-Manager-v$VERSION-macos-arm64.zip"

"$PROJECT_ROOT/scripts/build_macos_app.sh"
mkdir -p "$DIST"
rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --keepParent "$STAGED_APP" "$ARCHIVE"

shasum -a 256 "$ARCHIVE"
echo "Packaged: $ARCHIVE"
