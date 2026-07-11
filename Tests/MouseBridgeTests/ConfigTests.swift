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
        let config = AppConfig(backAction: " CMD+R ", scrollLines: 99, primaryDPI: 9999)
        XCTAssertEqual(config.backAction, "cmd+r")
        XCTAssertEqual(config.primaryDPI, 4000)
        XCTAssertEqual(config.scrollLines, 20)
    }

    func testLegacyConfigMigratesWithDefaults() throws {
        let data = Data(#"{"backAction":" CMD+R ","primaryDPI":1200,"secondaryDPI":400,"dpiButtonAction":"dpi:cycle"}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.schemaVersion, AppConfig.currentSchemaVersion)
        XCTAssertEqual(config.backAction, "cmd+r")
        XCTAssertEqual(config.primaryDPI, 1200)
        XCTAssertEqual(config.scrollLines, 0)
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
}
