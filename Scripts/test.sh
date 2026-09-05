#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="/private/tmp/codex-letgo-build"

export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export XDG_CACHE_HOME="$BUILD_ROOT/cache"
export CODE_SIGNING_ALLOWED=NO
export CODE_SIGNING_REQUIRED=NO
/bin/mkdir -p "$BUILD_ROOT/module-cache" "$BUILD_ROOT/cache" "$BUILD_ROOT/config" "$BUILD_ROOT/security"

cd "$PROJECT_ROOT"
/usr/bin/xattr -cr "$BUILD_ROOT" 2>/dev/null || true
swift test \
    --disable-sandbox \
    --scratch-path "$BUILD_ROOT" \
    --cache-path "$BUILD_ROOT/cache" \
    --config-path "$BUILD_ROOT/config" \
    --security-path "$BUILD_ROOT/security"
