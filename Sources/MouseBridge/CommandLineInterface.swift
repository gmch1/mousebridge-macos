import ApplicationServices
import Foundation

@MainActor
enum CommandLineInterface {
    static func run(arguments: [String]) -> Int? {
        guard let command = arguments.first else { return nil }
        switch command {
        case "config": return runConfig(Array(arguments.dropFirst()))
        case "launch-at-login": return runLaunchAtLogin(Array(arguments.dropFirst()))
        case "diagnose":
            print("config=\(ConfigStore.shared.fileURL.path)")
            print("log=\(DiagnosticLog.shared.fileURL.path)")
            print("accessibility=\(AXIsProcessTrusted())")
            print("input-monitoring=\(CGPreflightListenEventAccess())")
            print("launch-at-login=\(LaunchAtLoginController.status.description)")
            return 0
        case "help", "--help", "-h":
            printHelp()
            return 0
        default: return nil
        }
    }

    private static func runLaunchAtLogin(_ arguments: [String]) -> Int {
        guard arguments.count == 1 else {
            return fail("用法：MouseBridge launch-at-login status|enable|disable", code: 2)
        }
        do {
            switch arguments[0] {
            case "status":
                print(LaunchAtLoginController.status.description)
            case "enable":
                try LaunchAtLoginController.setEnabled(true)
                print(LaunchAtLoginController.status.description)
            case "disable":
                try LaunchAtLoginController.setEnabled(false)
                print(LaunchAtLoginController.status.description)
            default:
                return fail("未知 launch-at-login 操作：\(arguments[0])", code: 2)
            }
            return 0
        } catch {
            return fail("登录启动设置失败：\(error.localizedDescription)")
        }
    }

    private static func runConfig(_ arguments: [String]) -> Int {
        guard let operation = arguments.first else {
            printHelp()
            return 2
        }
        switch operation {
        case "path":
            print(ConfigStore.shared.fileURL.path)
            return 0
        case "get":
            do {
                FileHandle.standardOutput.write(try ConfigStore.shared.config.prettyJSONData())
                FileHandle.standardOutput.write(Data("\n".utf8))
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        case "set":
            guard arguments.count == 3 else {
                return fail("用法：MouseBridge config set <key> <value>", code: 2)
            }
            var config = ConfigStore.shared.config
            let key = arguments[1]
            let value = arguments[2]
            switch key {
            case "middle": config.middleAction = value
            case "back": config.backAction = value
            case "forward": config.forwardAction = value
            case "reverse-vertical":
                guard let parsed = parseBool(value) else { return fail("布尔值应为 true/false", code: 2) }
                config.reverseVerticalScroll = parsed
            case "reverse-horizontal":
                guard let parsed = parseBool(value) else { return fail("布尔值应为 true/false", code: 2) }
                config.reverseHorizontalScroll = parsed
            case "scroll-lines":
                guard let parsed = Int(value), (0...20).contains(parsed) else { return fail("scroll-lines 应为 0–20", code: 2) }
                config.scrollLines = parsed
            case "dpi":
                guard let parsed = Int(value), (400...4000).contains(parsed) else { return fail("dpi 应为 400–4000", code: 2) }
                config.primaryDPI = parsed
            default:
                return fail("未知配置项：\(key)", code: 2)
            }
            guard [config.middleAction, config.backAction, config.forwardAction].allSatisfy(ShortcutExecutor.isValid) else {
                return fail("快捷键格式无效", code: 2)
            }
            do {
                try ConfigStore.shared.save(config)
                print("ok")
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        default:
            return fail("未知 config 操作：\(operation)", code: 2)
        }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
        default: return nil
        }
    }

    private static func fail(_ message: String, code: Int = 1) -> Int {
        FileHandle.standardError.write(Data("MouseBridge: \(message)\n".utf8))
        return code
    }

    private static func printHelp() {
        print("""
        MouseBridge commands:
          MouseBridge config path
          MouseBridge config get
          MouseBridge config set middle|back|forward <shortcut|none>
          MouseBridge config set reverse-vertical|reverse-horizontal <true|false>
          MouseBridge config set scroll-lines <0-20>
          MouseBridge config set dpi <400-4000>
          MouseBridge launch-at-login status|enable|disable
          MouseBridge diagnose
        """)
    }
}
