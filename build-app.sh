#!/bin/zsh
set -eu

ROOT=${0:A:h}
APP="$ROOT/dist/MouseBridge.app"
CONTENTS="$APP/Contents"
VERSION=${VERSION:-0.2.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.module-cache"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    unset SDKROOT
    SWIFT_BIN=$(xcrun --find swift)
else
    SWIFT_BIN=$(command -v swift)
    COMPAT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
    [[ -d "$COMPAT_SDK" ]] && export SDKROOT="$COMPAT_SDK"
fi

"$SWIFT_BIN" test --disable-sandbox --package-path "$ROOT"
"$SWIFT_BIN" build -c release --disable-sandbox --package-path "$ROOT"
"$ROOT/.build/release/MouseBridge" --self-test
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/MouseBridge" "$CONTENTS/MacOS/MouseBridge"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Development only. A stable local requirement prevents every rebuild from
    # creating a new TCC identity, but is not suitable for distribution.
    codesign --force --sign - \
        --identifier io.github.mousebridge.macos \
        --requirements '=designated => identifier "io.github.mousebridge.macos"' \
        "$APP"
else
    codesign --force --options runtime --timestamp \
        --identifier io.github.mousebridge.macos \
        --sign "$SIGN_IDENTITY" \
        "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "$APP"
