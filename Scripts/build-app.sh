#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$PROJECT_ROOT/outputs"
BUILD_ROOT="/private/tmp/codex-letgo-xcode-derived"
STAGING_ROOT="/private/tmp/codex-letgo-package"
APP_BUNDLE="$STAGING_ROOT/Let Go.app"
OUTPUT_APP="$OUTPUT_DIRECTORY/Let Go.app"
OUTPUT_ZIP="$OUTPUT_DIRECTORY/Let-Go-macOS.zip"
SIGNING_IDENTITY="${LETGO_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${LETGO_NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && -z "$SIGNING_IDENTITY" ]]; then
    print -u2 "LETGO_NOTARY_PROFILE requires a Developer ID identity in LETGO_SIGNING_IDENTITY."
    exit 1
fi

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

if [[ -n "$SIGNING_IDENTITY" ]]; then
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"
    print "Signed with Developer ID: $SIGNING_IDENTITY"
else
    /usr/bin/codesign --force --sign - "$APP_BUNDLE"
    print "Created an ad-hoc signed development build."
fi

/usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/touch "$APP_BUNDLE"
/bin/mkdir -p "$OUTPUT_DIRECTORY"
/bin/rm -rf "$OUTPUT_APP"
/usr/bin/ditto "$APP_BUNDLE" "$OUTPUT_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"

if [[ -n "$NOTARY_PROFILE" ]]; then
    print "Submitting the signed archive to Apple for notarization…"
    /usr/bin/xcrun notarytool submit \
        "$OUTPUT_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    /usr/bin/xcrun stapler staple "$APP_BUNDLE"
    /usr/bin/xcrun stapler validate "$APP_BUNDLE"

    /bin/rm -rf "$OUTPUT_APP"
    /bin/rm -f "$OUTPUT_ZIP"
    /usr/bin/ditto "$APP_BUNDLE" "$OUTPUT_APP"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$OUTPUT_APP"
    print "Created a Developer ID signed and notarized release build."
fi

print "$OUTPUT_ZIP"
