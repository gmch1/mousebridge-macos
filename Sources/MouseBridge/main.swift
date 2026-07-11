// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run() ? 0 : 1)
} else if let code = MainActor.assumeIsolated({
    CommandLineInterface.run(arguments: Array(CommandLine.arguments.dropFirst()))
}) {
    exit(Int32(code))
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
