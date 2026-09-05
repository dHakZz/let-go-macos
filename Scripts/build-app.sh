#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$PROJECT_ROOT/outputs"
BUILD_ROOT="/private/tmp/codex-letgo-xcode-derived"
STAGING_ROOT="/private/tmp/codex-letgo-package"
APP_BUNDLE="$STAGING_ROOT/Let Go.app"
OUTPUT_APP="$OUTPUT_DIRECTORY/Let Go.app"
OUTPUT_ZIP="$OUTPUT_DIRECTORY/Let-Go-macOS.zip"

cd "$PROJECT_ROOT"
xcodebuild \
    -project "$PROJECT_ROOT/LetGo.xcodeproj" \
    -scheme "Let Go" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_ROOT" \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

BUILT_APP="$BUILD_ROOT/Build/Products/Release/Let Go.app"

if [[ "$APP_BUNDLE" != "/private/tmp/codex-letgo-package/Let Go.app" ]] || \
   [[ "$OUTPUT_APP" != "$PROJECT_ROOT/outputs/Let Go.app" ]] || \
   [[ "$OUTPUT_ZIP" != "$PROJECT_ROOT/outputs/Let-Go-macOS.zip" ]]; then
    print -u2 "Refusing to replace an unexpected packaging path."
    exit 1
fi

/bin/rm -rf "$APP_BUNDLE"
/bin/rm -f "$OUTPUT_ZIP"
/bin/mkdir -p "$STAGING_ROOT"
/usr/bin/ditto "$BUILT_APP" "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"

if [[ -n "${LETGO_SUPPORT_URL:-}" ]]; then
    /usr/libexec/PlistBuddy \
        -c "Set :LetGoSupportURL ${LETGO_SUPPORT_URL}" \
        "$APP_BUNDLE/Contents/Info.plist"
fi

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/touch "$APP_BUNDLE"
/bin/mkdir -p "$OUTPUT_DIRECTORY"
/bin/rm -rf "$OUTPUT_APP"
/usr/bin/ditto "$APP_BUNDLE" "$OUTPUT_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"

print "$OUTPUT_ZIP"
