#!/bin/zsh
set -eu

ROOT=${0:A:h}
APP="$ROOT/dist/MouseBridge.app"
CONTENTS="$APP/Contents"
VERSION=${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")}
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
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Legal"
cp "$ROOT/.build/release/MouseBridge" "$CONTENTS/MacOS/MouseBridge"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/Legal/GPL-3.0.txt"
cp "$ROOT/COPYRIGHT" "$CONTENTS/Resources/Legal/COPYRIGHT"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/Legal/THIRD_PARTY_NOTICES.md"
cp "$ROOT/SOURCE.md" "$CONTENTS/Resources/Legal/SOURCE.md"
cp "$ROOT/LICENSES/Apache-2.0.txt" "$CONTENTS/Resources/Legal/Apache-2.0.txt"
cp "$ROOT/LICENSES/GPL-2.0.txt" "$CONTENTS/Resources/Legal/GPL-2.0.txt"
cp "$ROOT/LICENSES/Scroll-Reverser-NOTICE.txt" "$CONTENTS/Resources/Legal/Scroll-Reverser-NOTICE.txt"
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
