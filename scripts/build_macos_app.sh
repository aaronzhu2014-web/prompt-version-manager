#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$PROJECT_ROOT/Prompt Version Manager.app"
STAGING_ROOT="${TMPDIR:-/tmp}/prompt-version-manager-build"
STAGED_APP="$STAGING_ROOT/Prompt Version Manager.app"
PLIST="$PROJECT_ROOT/Packaging/Info.plist"
ICON="$PROJECT_ROOT/Assets/AppIcon.icns"
BUILD_ROOT="$PROJECT_ROOT/.build/swiftpm"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
CLANG_CACHE="$PROJECT_ROOT/.build/clang-cache"
SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

mkdir -p "$MODULE_CACHE" "$CLANG_CACHE"
cd "$PROJECT_ROOT"

CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift build \
    -c release \
    --sdk "$SDK_PATH" \
    --scratch-path "$BUILD_ROOT" \
    --product PromptVersionManager

BIN_PATH="$(
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build \
        -c release \
        --sdk "$SDK_PATH" \
        --scratch-path "$BUILD_ROOT" \
        --show-bin-path
)"

rm -rf "$STAGING_ROOT" "$APP"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
/usr/bin/ditto "$PLIST" "$STAGED_APP/Contents/Info.plist"
/usr/bin/ditto "$ICON" "$STAGED_APP/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$BIN_PATH/PromptVersionManager" "$STAGED_APP/Contents/MacOS/prompt-version-manager"
chmod +x "$STAGED_APP/Contents/MacOS/prompt-version-manager"

if command -v codesign >/dev/null 2>&1; then
    xattr -cr "$STAGED_APP"
    codesign --force --deep --sign - "$STAGED_APP" >/dev/null
    xattr -cr "$STAGED_APP"
fi

codesign --verify --deep --strict "$STAGED_APP"
/usr/bin/ditto --norsrc "$STAGED_APP" "$APP"
xattr -cr "$APP"

echo "Built: $APP"
