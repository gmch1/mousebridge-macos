// SPDX-License-Identifier: GPL-3.0-or-later

import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var description: String {
        switch self {
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        case .requiresApproval: return "requires-approval"
        case .unavailable: return "unavailable"
        }
    }
}

@MainActor
enum LaunchAtLoginController {
    static var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound:
            // macOS may report .notFound before the first registration because
            // Background Task Management has not created a record for the app.
            return .disabled
        @unknown default: return .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status != .disabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
