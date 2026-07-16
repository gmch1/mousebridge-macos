// SPDX-License-Identifier: GPL-3.0-or-later
// Gesture state machine adapted from TapBind / MiddleClick and reimplemented
// for configurable MouseBridge shortcut actions.

import Foundation

struct TrackpadTouchPoint: Equatable {
    let x: Double
    let y: Double
}

final class MultitouchGestureRecognizer {
    struct Settings: Equatable {
        var enabled: Bool
        var fingerCount: Int
        var tapEnabled: Bool
        var allowMoreFingers: Bool
        var maximumTapDuration: TimeInterval
        var maximumTapMovement: Double
    }

    private(set) var isPhysicalClickArmed = false

    private var settings: Settings
    private var contactActive = false
    private var physicalClickConsumed = false
    private var touchStartTime: TimeInterval?
    private var touchStartPosition: TrackpadTouchPoint?
    private var touchEndPosition: TrackpadTouchPoint?
    private var tapDisqualified = false

    init(settings: Settings) {
        self.settings = settings
    }

    func update(settings newSettings: Settings) {
        guard settings != newSettings else { return }
        settings = newSettings
        resetSequence()
    }

    /// Returns true when a configured multi-finger tap has completed.
    func processFrame(points: [TrackpadTouchPoint], timestamp: TimeInterval) -> Bool {
        let countMatches = settings.allowMoreFingers
            ? points.count >= settings.fingerCount
            : points.count == settings.fingerCount
        let aggregate: TrackpadTouchPoint? = countMatches
            ? points.prefix(settings.fingerCount).reduce(TrackpadTouchPoint(x: 0, y: 0)) { partial, point in
                TrackpadTouchPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            : nil
        return processFrame(fingerCount: points.count, aggregatePosition: aggregate, timestamp: timestamp)
    }

    /// Allocation-free entry point used by the high-frequency device callback.
    func processFrame(
        fingerCount: Int,
        aggregatePosition: TrackpadTouchPoint?,
        timestamp: TimeInterval
    ) -> Bool {
        guard settings.enabled else {
            resetSequence()
            return false
        }

        guard fingerCount > 0 else { return finishTouchSequence(timestamp: timestamp) }

        if !contactActive {
            contactActive = true
            physicalClickConsumed = false
            touchStartTime = timestamp
            touchStartPosition = nil
            touchEndPosition = nil
            tapDisqualified = false
        }

        if let touchStartTime,
           timestamp - touchStartTime > settings.maximumTapDuration {
            tapDisqualified = true
        }

        let countMatches = settings.allowMoreFingers
            ? fingerCount >= settings.fingerCount
            : fingerCount == settings.fingerCount
        isPhysicalClickArmed = countMatches && !physicalClickConsumed

        if !settings.allowMoreFingers && fingerCount > settings.fingerCount {
            tapDisqualified = true
        }

        if countMatches, let aggregatePosition {
            if touchStartPosition == nil { touchStartPosition = aggregatePosition }
            touchEndPosition = aggregatePosition
        }

        return false
    }

    /// Consumes one physical click while the configured number of fingers is down.
    func consumePhysicalClickIfArmed() -> Bool {
        guard settings.enabled, isPhysicalClickArmed, !physicalClickConsumed else { return false }
        physicalClickConsumed = true
        isPhysicalClickArmed = false
        return true
    }

    private func finishTouchSequence(timestamp: TimeInterval) -> Bool {
        defer { resetSequence() }
        guard contactActive,
              settings.tapEnabled,
              !physicalClickConsumed,
              !tapDisqualified,
              let touchStartTime,
              timestamp - touchStartTime <= settings.maximumTapDuration,
              let touchStartPosition,
              let touchEndPosition else {
            return false
        }

        let movement = abs(touchStartPosition.x - touchEndPosition.x)
            + abs(touchStartPosition.y - touchEndPosition.y)
        return movement < settings.maximumTapMovement
    }

    private func resetSequence() {
        contactActive = false
        physicalClickConsumed = false
        touchStartTime = nil
        touchStartPosition = nil
        touchEndPosition = nil
        tapDisqualified = false
        isPhysicalClickArmed = false
    }
}
