// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MouseBridge

final class ConfigTests: XCTestCase {
    func testDPIClampsToM750Range() {
        XCTAssertEqual(AppConfig.clampDPI(100), 400)
        XCTAssertEqual(AppConfig.clampDPI(1200), 1200)
        XCTAssertEqual(AppConfig.clampDPI(9000), 4000)
    }

    func testShortcutValidation() {
        XCTAssertTrue(ShortcutExecutor.isValid("cmd+r"))
        XCTAssertTrue(ShortcutExecutor.isValid("shift+cmd+z"))
        XCTAssertTrue(ShortcutExecutor.isValid("none"))
        XCTAssertTrue(ShortcutExecutor.isValid(""))
        XCTAssertFalse(ShortcutExecutor.isValid("cmd+not-a-key"))
    }

    func testConfigNormalization() {
        let config = AppConfig(
            backAction: " CMD+R ",
            scrollLines: 99,
            primaryDPI: 9999,
            trackpadFingerCount: 9,
            trackpadAction: " CMD+W ",
            trackpadTapMaxMilliseconds: 5,
            trackpadTapMaxMovement: 2
        )
        XCTAssertEqual(config.backAction, "cmd+r")
        XCTAssertEqual(config.primaryDPI, 4000)
        XCTAssertEqual(config.scrollLines, 20)
        XCTAssertEqual(config.trackpadFingerCount, 5)
        XCTAssertEqual(config.trackpadAction, "cmd+w")
        XCTAssertEqual(config.trackpadTapMaxMilliseconds, 50)
        XCTAssertEqual(config.trackpadTapMaxMovement, 0.5)
    }

    func testLegacyConfigMigratesWithDefaults() throws {
        let data = Data(#"{"backAction":" CMD+R ","primaryDPI":1200,"secondaryDPI":400,"dpiButtonAction":"dpi:cycle"}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.schemaVersion, AppConfig.currentSchemaVersion)
        XCTAssertEqual(config.backAction, "cmd+r")
        XCTAssertEqual(config.primaryDPI, 1200)
        XCTAssertEqual(config.scrollLines, 0)
        XCTAssertFalse(config.trackpadGestureEnabled)
        XCTAssertEqual(config.trackpadFingerCount, 3)
        XCTAssertEqual(config.trackpadAction, "cmd+w")
    }

    func testThreeFingerTapTriggers() {
        let recognizer = MultitouchGestureRecognizer(settings: trackpadSettings())
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.2), timestamp: 10))
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.205), timestamp: 10.1))
        XCTAssertTrue(recognizer.processFrame(points: [], timestamp: 10.2))
    }

    func testTapRejectsMovementTimeoutAndExtraFinger() {
        var recognizer = MultitouchGestureRecognizer(settings: trackpadSettings())
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.2), timestamp: 10))
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.3), timestamp: 10.1))
        XCTAssertFalse(recognizer.processFrame(points: [], timestamp: 10.2))

        recognizer = MultitouchGestureRecognizer(settings: trackpadSettings())
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.2), timestamp: 20))
        XCTAssertFalse(recognizer.processFrame(points: [], timestamp: 20.31))

        recognizer = MultitouchGestureRecognizer(settings: trackpadSettings())
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.2), timestamp: 30))
        XCTAssertFalse(recognizer.processFrame(points: points(4, x: 0.2), timestamp: 30.1))
        XCTAssertFalse(recognizer.processFrame(points: [], timestamp: 30.2))
    }

    func testPhysicalClickTriggersOnceAndSuppressesTapDuplicate() {
        let recognizer = MultitouchGestureRecognizer(settings: trackpadSettings())
        XCTAssertFalse(recognizer.processFrame(points: points(3, x: 0.2), timestamp: 10))
        XCTAssertTrue(recognizer.isPhysicalClickArmed)
        XCTAssertTrue(recognizer.consumePhysicalClickIfArmed())
        XCTAssertFalse(recognizer.consumePhysicalClickIfArmed())
        XCTAssertFalse(recognizer.processFrame(points: [], timestamp: 10.1))
    }

    func testAllowMoreFingersArmsPhysicalClick() {
        var settings = trackpadSettings()
        settings.allowMoreFingers = true
        let recognizer = MultitouchGestureRecognizer(settings: settings)
        XCTAssertFalse(recognizer.processFrame(points: points(4, x: 0.2), timestamp: 10))
        XCTAssertTrue(recognizer.consumePhysicalClickIfArmed())
    }

    func testDPIRangeEncodingDecodes() {
        let values = HIDPPController.decodeDPIList([0x01, 0x90, 0xE0, 0x64, 0x0F, 0xA0, 0, 0])
        XCTAssertEqual(values.first, 400)
        XCTAssertEqual(values.last, 4000)
        XCTAssertEqual(values.count, 37)
    }

    func testVerticalScrollTransform() {
        let reversed = ScrollTransform.vertical(axis: 1, point: 11, fixed: 1.1, continuous: false, reverse: true, lines: 0)
        XCTAssertEqual(reversed?.axis, -1)
        XCTAssertEqual(reversed?.point, -11)
        XCTAssertEqual(reversed?.fixed, -1.1)

        let stepped = ScrollTransform.vertical(axis: -1, point: -1, fixed: -0.1, continuous: false, reverse: true, lines: 4)
        XCTAssertEqual(stepped?.axis, 4)
        XCTAssertNil(stepped?.point)
        XCTAssertEqual(stepped?.adjustsDiscreteStep, true)
    }

    private func trackpadSettings() -> MultitouchGestureRecognizer.Settings {
        MultitouchGestureRecognizer.Settings(
            enabled: true,
            fingerCount: 3,
            tapEnabled: true,
            allowMoreFingers: false,
            maximumTapDuration: 0.3,
            maximumTapMovement: 0.05
        )
    }

    private func points(_ count: Int, x: Double) -> [TrackpadTouchPoint] {
        (0..<count).map { index in
            TrackpadTouchPoint(x: x + Double(index) * 0.01, y: 0.4)
        }
    }
}
