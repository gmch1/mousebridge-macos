import Foundation

enum SelfTest {
    static func run() -> Bool {
        var normalized = AppConfig()
        normalized.scrollLines = 99
        normalized.normalize()
        let dpiList = HIDPPController.decodeDPIList([0x01, 0x90, 0xE0, 0x64, 0x0F, 0xA0, 0, 0])
        let checks: [(String, Bool)] = [
            ("DPI lower bound", AppConfig.clampDPI(100) == 400),
            ("DPI unchanged", AppConfig.clampDPI(1200) == 1200),
            ("DPI upper bound", AppConfig.clampDPI(9000) == 4000),
            ("DPI range decoding", dpiList.first == 400 && dpiList.last == 4000 && dpiList.count == 37),
            ("scroll lines upper bound", normalized.scrollLines == 20),
            ("shortcut cmd+r", ShortcutExecutor.isValid("cmd+r")),
            ("shortcut modifiers", ShortcutExecutor.isValid("shift+cmd+z")),
            ("disabled action", ShortcutExecutor.isValid("none")),
            ("invalid shortcut", !ShortcutExecutor.isValid("cmd+not-a-key")),
        ]
        for (name, passed) in checks {
            print("\(passed ? "PASS" : "FAIL") \(name)")
        }
        return checks.allSatisfy(\.1)
    }
}
