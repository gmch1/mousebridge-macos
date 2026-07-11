// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    static let verboseEvents = ProcessInfo.processInfo.environment["MOUSEBRIDGE_DEBUG_EVENTS"] == "1"

    let fileURL: URL
    private let queue = DispatchQueue(label: "mousebridge.diagnostic-log")
    private var handle: FileHandle?
    private let formatter = ISO8601DateFormatter()

    private init() {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        fileURL = logs.appendingPathComponent("MouseBridge.log")
    }

    func resetForLaunch() {
        queue.sync {
            try? handle?.close()
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: fileURL)
            writeUnlocked("=== MouseBridge diagnostic session started ===")
        }
    }

    func write(_ message: String) {
        queue.async { [weak self] in self?.writeUnlocked(message) }
    }

    func writeEvent(_ message: String) {
        guard Self.verboseEvents else { return }
        write(message)
    }

    private func writeUnlocked(_ message: String) {
        guard let data = "\(formatter.string(from: Date())) \(message)\n".data(using: .utf8) else { return }
        do {
            if handle == nil { handle = try FileHandle(forWritingTo: fileURL) }
            try handle?.seekToEnd()
            try handle?.write(contentsOf: data)
            try handle?.synchronize()
        } catch {
            // Diagnostics must never interfere with input handling.
        }
    }
}
