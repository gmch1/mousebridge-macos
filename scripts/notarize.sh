#!/bin/zsh
set -eu

ROOT=${0:A:h:h}
APP=${1:-$ROOT/dist/MouseBridge.app}
PROFILE=${NOTARY_PROFILE:-mousebridge-notary}
ZIP="$ROOT/dist/MouseBridge-notarize.zip"

if [[ ! -d "$APP" ]]; then
    echo "App not found: $APP" >&2
    exit 1
fi

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -vv --type execute "$APP"
echo "$APP"
