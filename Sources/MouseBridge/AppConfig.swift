import Darwin
import Foundation

struct AppConfig: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion = Self.currentSchemaVersion
    var middleAction = ""
    var backAction = "cmd+r"
    var forwardAction = "cmd+w"
    var reverseVerticalScroll = false
    var reverseHorizontalScroll = false
    var scrollLines = 0
    var primaryDPI = 1000

    init(
        middleAction: String = "",
        backAction: String = "cmd+r",
        forwardAction: String = "cmd+w",
        reverseVerticalScroll: Bool = false,
        reverseHorizontalScroll: Bool = false,
        scrollLines: Int = 0,
        primaryDPI: Int = 1000
    ) {
        self.middleAction = middleAction
        self.backAction = backAction
        self.forwardAction = forwardAction
        self.reverseVerticalScroll = reverseVerticalScroll
        self.reverseHorizontalScroll = reverseHorizontalScroll
        self.scrollLines = scrollLines
        self.primaryDPI = primaryDPI
        normalize()
    }

    mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        primaryDPI = Self.clampDPI(primaryDPI)
        scrollLines = min(20, max(0, scrollLines))
        middleAction = Self.normalizeAction(middleAction)
        backAction = Self.normalizeAction(backAction)
        forwardAction = Self.normalizeAction(forwardAction)
    }

    static func clampDPI(_ value: Int) -> Int { min(4000, max(400, value)) }

    private static func normalizeAction(_ action: String) -> String {
        action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case middleAction, backAction, forwardAction
        case reverseVerticalScroll, reverseHorizontalScroll, scrollLines
        case primaryDPI
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        middleAction = try values.decodeIfPresent(String.self, forKey: .middleAction) ?? ""
        backAction = try values.decodeIfPresent(String.self, forKey: .backAction) ?? "cmd+r"
        forwardAction = try values.decodeIfPresent(String.self, forKey: .forwardAction) ?? "cmd+w"
        reverseVerticalScroll = try values.decodeIfPresent(Bool.self, forKey: .reverseVerticalScroll) ?? false
        reverseHorizontalScroll = try values.decodeIfPresent(Bool.self, forKey: .reverseHorizontalScroll) ?? false
        scrollLines = try values.decodeIfPresent(Int.self, forKey: .scrollLines) ?? 0
        primaryDPI = try values.decodeIfPresent(Int.self, forKey: .primaryDPI) ?? 1000
        normalize()
    }

    func prettyJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum ConfigStoreError: LocalizedError {
    case createDirectory(Error)
    case read(Error)
    case decode(Error)
    case write(Error)

    var errorDescription: String? {
        switch self {
        case .createDirectory(let error): return "无法创建配置目录：\(error.localizedDescription)"
        case .read(let error): return "无法读取配置：\(error.localizedDescription)"
        case .decode(let error): return "配置格式无效：\(error.localizedDescription)"
        case .write(let error): return "无法写入配置：\(error.localizedDescription)"
        }
    }
}

@MainActor
final class ConfigStore {
    static let shared = ConfigStore()
    static let changed = Notification.Name("MouseBridgeConfigChanged")

    private(set) var config = AppConfig()
    private(set) var lastError: Error?
    let directoryURL: URL
    let fileURL: URL

    private var watcher: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    private init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = applicationSupport.appendingPathComponent("MouseBridge", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("config.json")
        let legacyURL = applicationSupport
            .appendingPathComponent("LogiLite", isDirectory: true)
            .appendingPathComponent("config.json")

        do {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                throw ConfigStoreError.createDirectory(error)
            }
            if !FileManager.default.fileExists(atPath: fileURL.path),
               FileManager.default.fileExists(atPath: legacyURL.path) {
                try FileManager.default.copyItem(at: legacyURL, to: fileURL)
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                config = try Self.readConfig(at: fileURL)
                // Rewrite successfully decoded legacy schemas in canonical v2
                // form so removed keys do not linger indefinitely.
                try config.prettyJSONData().write(to: fileURL, options: .atomic)
            } else {
                try config.prettyJSONData().write(to: fileURL, options: .atomic)
            }
        } catch {
            lastError = error
            preserveCorruptConfigIfNeeded()
            config = AppConfig()
        }
    }

    func save(_ newConfig: AppConfig) throws {
        var normalized = newConfig
        normalized.normalize()
        do {
            try normalized.prettyJSONData().write(to: fileURL, options: .atomic)
        } catch {
            let wrapped = ConfigStoreError.write(error)
            lastError = wrapped
            throw wrapped
        }
        lastError = nil
        if config != normalized {
            config = normalized
            NotificationCenter.default.post(name: Self.changed, object: normalized)
        }
    }

    func reloadFromDisk() {
        do {
            let loaded = try Self.readConfig(at: fileURL)
            lastError = nil
            if loaded != config {
                config = loaded
                NotificationCenter.default.post(name: Self.changed, object: loaded)
                DiagnosticLog.shared.write("configuration reloaded from disk")
            }
        } catch {
            lastError = error
            DiagnosticLog.shared.write("configuration reload FAILED: \(error.localizedDescription)")
        }
    }

    func startWatching() {
        guard watcher == nil else { return }
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            DiagnosticLog.shared.write("configuration watcher open FAILED errno=\(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            reloadWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reloadFromDisk() }
            reloadWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        watcher = source
        source.resume()
    }

    func stopWatching() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        watcher?.cancel()
        watcher = nil
    }

    private static func readConfig(at url: URL) throws -> AppConfig {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw ConfigStoreError.read(error) }
        do { return try JSONDecoder().decode(AppConfig.self, from: data) }
        catch { throw ConfigStoreError.decode(error) }
    }

    private func preserveCorruptConfigIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let backup = directoryURL.appendingPathComponent("config.corrupt-\(timestamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
