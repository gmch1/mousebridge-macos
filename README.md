# MouseBridge for macOS

English | [简体中文](README.zh-CN.md)

MouseBridge is a GPL-3.0-or-later native macOS foundation for mouse button
mapping, mouse-only wheel control, and Logitech HID++ hardware DPI
configuration. It was created for people who only need a few mouse features
and do not want to keep a large vendor suite running in the background.

The project deliberately exposes useful low-level capabilities through a small
AppKit UI, a versioned JSON file, and a CLI. This makes it practical for users,
scripts, and coding agents such as Codex to extend without first replacing a
large framework.

[Download the latest release](https://github.com/gmch1/mousebridge-macos/releases)

## Project goals

- Stay small, native, understandable, and easy to modify.
- Provide reliable button, wheel, and hardware DPI primitives.
- Keep configuration local and automation-friendly.
- Make support for another mouse start with a device profile instead of a UI
  rewrite.
- Avoid accounts, cloud services, telemetry, and Electron, Qt, or Python
  runtimes.

MouseBridge is not intended to reproduce every feature in Logitech Options+.
It currently does not manage gestures, per-application profiles, Flow, firmware
updates, battery reporting, or Logitech cameras and keyboards.

## Current features

- Map middle, back, and forward buttons to shortcuts such as `cmd+r`.
- Disable a button with `none`, or leave it empty to pass it through.
- Reverse vertical and horizontal mouse scrolling without changing trackpad
  scrolling.
- Set a discrete-wheel amount from 0–20 (`0` keeps the macOS default).
- Query DPI values reported by Logitech HID++ feature `0x2201` and select them
  through a 0–100% slider.
- Reload JSON configuration after scripts or coding agents edit it.
- Start at login through `SMAppService`.
- Write local diagnostics to `~/Library/Logs/MouseBridge.log`.

## Tested hardware and environment

The first and currently only hardware profile tested on a physical device is:

| Item | Tested value |
| --- | --- |
| Mouse | Logitech Signature Plus M750 L |
| Connection | Bluetooth |
| USB/HID identity | VID `0x046D`, PID `0xB02C` |
| DPI reported by device | 400–4000 DPI, 100-DPI steps, 37 values |
| Mac | Apple silicon (`arm64`) |
| Test system | macOS 26.5.2 |
| App | MouseBridge 0.2.0 |

Physical-device verification currently covers Bluetooth discovery, back and
forward button mapping, vertical scroll reversal, and reading/applying hardware
DPI. Scroll calculations, configuration validation, shortcut validation, and
DPI decoding also have automated tests.

The following paths are implemented but have not yet received the same physical
hardware coverage: horizontal scrolling, middle-button mapping, Logitech Bolt
receivers, Intel Macs, and other Logitech mouse models. macOS 13 is the minimum
deployment target, but it has not yet been tested across every macOS release.
Please open an issue with the product name, connection type, VID/PID, macOS
version, and diagnostic log when reporting compatibility results.

## Permissions

Accessibility permission is required to intercept mouse buttons, modify scroll
events, and post shortcuts. Input Monitoring is strongly recommended for
reliable mouse-versus-trackpad classification and was enabled in the tested
environment. macOS requires the user to approve privacy permissions manually;
an application cannot silently grant them to itself.

The settings window links directly to the relevant System Settings panes.

## Installation

Download the ZIP from [GitHub Releases](https://github.com/gmch1/mousebridge-macos/releases),
extract it, and move `MouseBridge.app` to `/Applications`.

Releases labeled **Pre-release** are ad-hoc signed and may require manual
Gatekeeper approval. Developer ID signed and notarized builds are published as
regular releases.

## Development (contributors)

```bash
zsh build-app.sh
open dist/MouseBridge.app
```

The build script uses `/Applications/Xcode.app` when available, runs XCTest and
the binary self-test, builds a release executable, and assembles the app bundle.
Its default ad-hoc signature is intended only for local contributor builds.

For a Developer ID build:

```bash
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
VERSION=0.2.1 BUILD_NUMBER=2 zsh build-app.sh
NOTARY_PROFILE=mousebridge-notary zsh scripts/notarize.sh
```

## Release maintenance

Pushing a semantic version tag such as `v0.2.1` verifies that the tag matches
`Info.plist`, runs all tests, builds the app, creates a ZIP and SHA-256 checksum,
and publishes a GitHub Release. Without Apple signing secrets, the workflow
publishes an explicitly labeled pre-release.

See [docs/RELEASING.md](docs/RELEASING.md) for the complete procedure.

## Configuration and CLI

Configuration is stored at:

```text
~/Library/Application Support/MouseBridge/config.json
```

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

## Architecture and extension points

- `AppConfig` and `ConfigStore`: versioned JSON, validation, atomic writes, and
  directory watching.
- `EventTapController`: button interception, source classification, and wheel
  transformation.
- `ScrollTransform`: pure and tested discrete-scroll calculations.
- `ShortcutExecutor`: compact shortcut parser and Quartz event injection.
- `HIDPPController`: profile-based IOKit transport, DPI discovery, serialized
  requests, disconnect-safe cleanup, and best-effort DPI restoration.
- `SettingsWindowController`: small AppKit configuration UI.
- `CommandLineInterface`: automation surface for scripts and coding agents.

Adding a device begins with `MouseDeviceProfile`; the transport layer does not
need to know the product's marketing name.

## Open-source foundations

MouseBridge builds on interoperability knowledge and implementation patterns
from:

- [Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser) (Apache-2.0):
  its public implementation helped explain trackpad/mouse gesture timing and
  why reliable reversal updates both Quartz and the underlying IOHID scroll
  payload.
- [Solaar](https://github.com/pwr-Solaar/Solaar) (GPL-2.0-or-later): its HID++
  adjustable-DPI list decoding informed the corresponding MouseBridge logic.

The combined MouseBridge work is distributed under GPL-3.0-or-later. Original
third-party portions retain their notices and license history. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES](LICENSES/).

## Compatibility and distribution note

For reliable scroll reversal, MouseBridge dynamically loads the private IOHID
bridge also documented by Scroll Reverser. It falls back to public Quartz
fields when those symbols are unavailable. Because private API behavior can
change between macOS releases, scroll handling needs regression testing on new
macOS versions. This also makes direct distribution more appropriate than the
Mac App Store.

## License

MouseBridge is free software distributed under
[GPL-3.0-or-later](LICENSE). Corresponding source is available in this
repository and with each GitHub Release. See [SOURCE.md](SOURCE.md).
