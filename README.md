# MouseBridge for macOS

MouseBridge is a small native macOS foundation for mouse button mapping,
discrete-wheel control, and Logitech HID++ hardware DPI configuration. The
first supported profile is the Logitech Signature Plus M750 L over Bluetooth
(`VID 0x046D`, `PID 0xB02C`).

It has no cloud service, account, telemetry, Electron, Qt, or Python runtime.

## Features

- Map middle, back, and forward buttons to shortcuts such as `cmd+r`.
- Disable a button with `none`, or leave it empty to pass it through.
- Reverse vertical and horizontal mouse scrolling without changing trackpad
  scrolling.
- Set a discrete-wheel step from 0–20 (`0` keeps the macOS default).
- Query the DPI values reported by HID++ feature `0x2201` and select them with
  a 0–100% slider. The M750 L reports 400–4000 DPI in 100-DPI steps.
- Reload the JSON configuration when scripts or coding agents edit it.
- Optional launch at login through `SMAppService`.
- Local diagnostic log at `~/Library/Logs/MouseBridge.log`.

## Permissions

Accessibility permission is required to intercept mouse buttons, modify
scrolling, and post shortcuts. Input Monitoring is optional for M750 operation
and improves mouse/trackpad source classification. The settings window links
directly to both System Settings panes.

macOS always requires the user to approve privacy permissions manually.

## Build and test

```bash
zsh build-app.sh
open dist/MouseBridge.app
```

The script uses a full `/Applications/Xcode.app` when available, runs the Swift
test target, builds a release executable, assembles an app bundle, and applies
a development ad-hoc signature.

For a Developer ID build:

```bash
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
VERSION=0.2.0 BUILD_NUMBER=2 zsh build-app.sh
NOTARY_PROFILE=mousebridge-notary zsh scripts/notarize.sh
```

The ad-hoc signature is for local development only. GitHub releases should be
Developer ID signed, hardened, timestamped, and notarized.

## Releases

Pushing a version tag such as `v0.2.0` runs the release workflow, verifies that
the tag matches `Info.plist`, runs the test suite, builds the app, creates a ZIP
and SHA-256 checksum, and publishes a GitHub Release. Without configured Apple
signing secrets, the same workflow publishes an explicitly labeled pre-release.

See [docs/RELEASING.md](docs/RELEASING.md) for signing secret names and the
release procedure.

## Configuration and CLI

Configuration is stored at:

```text
~/Library/Application Support/MouseBridge/config.json
```

Legacy `LogiLite/config.json` is migrated once. Schema v2 removes the old DPI
button/two-DPI fields. Corrupt files are preserved as
`config.corrupt-<timestamp>.json`.

```bash
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config get
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config set back cmd+r
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config set scroll-lines 4
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config set dpi 1200
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge launch-at-login status
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge launch-at-login enable
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge diagnose
```

An already-running app watches the configuration directory and applies valid
external changes automatically.

## Architecture

- `AppConfig` and `ConfigStore`: versioned JSON, migration, atomic writes, and
  directory watching.
- `EventTapController`: button interception, source classification, and wheel
  transformation.
- `ScrollTransform`: pure, tested discrete-scroll calculations.
- `ShortcutExecutor`: compact shortcut parser and Quartz injection.
- `HIDPPController`: profile-based IOKit transport, DPI discovery, serialized
  requests, disconnect-safe cleanup, and best-effort DPI restoration.
- `SettingsWindowController`: small AppKit configuration UI.
- `CommandLineInterface`: automation surface intended for scripts and coding
  agents.

Adding a device starts with a `MouseDeviceProfile`; transport code does not
need to know the product name.

## Compatibility note

For reliable scroll reversal, MouseBridge dynamically loads the same private
IOHID bridge used by Scroll Reverser. If those symbols are unavailable, it
falls back to public Quartz fields instead of failing to launch. This use of
private API means MouseBridge is intended for direct distribution rather than
the Mac App Store.

## License

MouseBridge is MIT licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for interoperability references and acknowledgements.
