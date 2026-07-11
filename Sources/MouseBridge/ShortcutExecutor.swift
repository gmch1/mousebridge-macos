import ApplicationServices
import Foundation

enum ShortcutExecutor {
    static let injectedMarker: Int64 = 0x4C4F4749

    static func execute(_ specification: String) {
        let value = specification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, value != "none" else {
            DiagnosticLog.shared.writeEvent("shortcut skipped specification=\(specification)")
            return
        }
        let parts = value.split(separator: "+").map(String.init)
        guard let keyName = parts.last, let keyCode = keyCodes[keyName] else {
            DiagnosticLog.shared.writeEvent("shortcut invalid key specification=\(specification)")
            return
        }

        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default:
                DiagnosticLog.shared.writeEvent("shortcut invalid modifier=\(modifier) specification=\(specification)")
                return
            }
        }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            DiagnosticLog.shared.writeEvent("shortcut event creation FAILED specification=\(specification)")
            return
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: injectedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: injectedMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        DiagnosticLog.shared.writeEvent("shortcut posted specification=\(specification) keyCode=\(keyCode) flags=\(flags.rawValue)")
    }

    static func isValid(_ specification: String) -> Bool {
        let value = specification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "none" { return true }
        let parts = value.split(separator: "+").map(String.init)
        guard let key = parts.last, keyCodes[key] != nil else { return false }
        return parts.dropLast().allSatisfy {
            ["cmd", "command", "shift", "opt", "option", "alt", "ctrl", "control"].contains($0)
        }
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "enter": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "delete": 51, "escape": 53, "left": 123, "right": 124, "down": 125,
        "up": 126,
    ]
}
