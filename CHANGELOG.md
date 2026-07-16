# Changelog

## Unreleased

- Add configurable 2–5-finger trackpad shortcut mapping for physical clicks
  and optional taps.
- Add native MultitouchSupport device handling with an allocation-free frame
  callback and no active listener while the feature is disabled or paused.
- Create the AppKit settings window lazily on first use instead of retaining
  all controls for the entire menu-bar session.
- Add schema-v3 JSON fields, CLI controls, AppKit settings, and gesture-state
  tests for the trackpad feature.

## 0.2.1 — 2026-07-12

- Relicense the combined project under GPL-3.0-or-later.
- Record Scroll Reverser and Solaar provenance without absolute non-copying claims.
- Bundle GPL, Apache, upstream NOTICE, and corresponding-source information in the app.

## 0.2.0 — 2026-07-12

First public preview of MouseBridge.

- Native AppKit menu-bar application for macOS 13 and newer.
- Logitech Signature Plus M750 L support over Bluetooth.
- Middle, back, and forward button shortcut mapping.
- Mouse-only vertical and horizontal scroll reversal.
- Configurable scroll amount from system default through 20 lines.
- Device-reported hardware DPI range and 0–100% DPI slider.
- Versioned JSON configuration, live reload, diagnostics, and CLI controls.
- Accessibility and Input Monitoring permission diagnostics.
- Login-at-launch support through `SMAppService`.
- XCTest coverage, warning-clean release builds, and automated release packaging.
