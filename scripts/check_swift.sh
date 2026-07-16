#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/.build/swiftpm"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
CLANG_CACHE="$PROJECT_ROOT/.build/clang-cache"
SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

mkdir -p "$MODULE_CACHE" "$CLANG_CACHE"
cd "$PROJECT_ROOT"

CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift run \
    --sdk "$SDK_PATH" \
    --scratch-path "$BUILD_ROOT" \
    PromptVersionCoreChecks
