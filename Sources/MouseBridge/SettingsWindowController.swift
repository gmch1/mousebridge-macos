// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let middleField = NSTextField()
    private let backField = NSTextField()
    private let forwardField = NSTextField()
    private let reverseVertical = NSButton(checkboxWithTitle: "反向垂直滚动（仅鼠标）", target: nil, action: nil)
    private let reverseHorizontal = NSButton(checkboxWithTitle: "反向水平滚动（仅鼠标）", target: nil, action: nil)
    private let scrollLinesSlider = NSSlider(value: 0, minValue: 0, maxValue: 20, target: nil, action: nil)
    private let scrollLinesValue = NSTextField(labelWithString: "跟随系统")
    private let dpiSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let dpiValue = NSTextField(labelWithString: "1000 DPI")
    private let dpiRange = NSTextField(labelWithString: "正在读取设备 DPI 范围…")
    private let connectionLabel = NSTextField(labelWithString: "M750：正在连接…")
    private let inputStatusLabel = NSTextField(labelWithString: "按键与滚轮：检查权限…")
    private let permissionStatusLabel = NSTextField(labelWithString: "权限：正在检查…")
    private let launchAtLogin = NSButton(checkboxWithTitle: "登录时自动启动", target: nil, action: nil)
    private let messageLabel = NSTextField(labelWithString: "")
    private var dpiValues = Array(stride(from: 400, through: 4000, by: 50))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MouseBridge 设置"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        loadConfig()
        refreshLaunchAtLogin()
        if let error = ConfigStore.shared.lastError {
            messageLabel.stringValue = error.localizedDescription
        }
    }

    required init?(coder: NSCoder) { nil }

    func setConnected(_ connected: Bool) {
        connectionLabel.stringValue = connected ? "M750：已连接" : "M750：未连接"
        connectionLabel.textColor = connected ? .systemGreen : .secondaryLabelColor
    }

    func setDPICapabilities(_ capabilities: HIDPPController.DPICapabilities) {
        guard !capabilities.values.isEmpty else { return }
        dpiValues = capabilities.values
        let source = capabilities.cameFromDevice ? "设备报告" : "兼容范围"
        dpiRange.stringValue = "\(source)：\(capabilities.minimum)–\(capabilities.maximum) DPI · \(capabilities.values.count) 档"
        dpiSlider.doubleValue = percent(forDPI: ConfigStore.shared.config.primaryDPI)
        updateDPIValue()
    }

    func setInputStatus(_ text: String, ready: Bool) {
        inputStatusLabel.stringValue = text
        inputStatusLabel.textColor = ready ? .systemGreen : .systemOrange
    }

    func setDPIApplyResult(_ success: Bool, value: Int) {
        messageLabel.textColor = success ? .systemGreen : .systemRed
        messageLabel.stringValue = success ? "已应用 \(value) DPI" : "配置已保存，但 \(value) DPI 应用失败"
    }

    func setPermissionStatus(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        let accessibility = accessibilityGranted ? "✅" : "⏳"
        let inputMonitoring = inputMonitoringGranted ? "✅" : "⏳"
        permissionStatusLabel.stringValue = "权限：辅助功能 \(accessibility)　输入监控 \(inputMonitoring)（触控板识别可选）"
        permissionStatusLabel.textColor = accessibilityGranted ? .systemGreen : .systemOrange
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "MouseBridge")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "原生 macOS 鼠标按键、滚轮与硬件 DPI 工具")
        subtitle.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "滚轮中键"), middleField],
            [NSTextField(labelWithString: "后退侧键"), backField],
            [NSTextField(labelWithString: "前进侧键"), forwardField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 330
        for field in [middleField, backField, forwardField] {
            field.placeholderString = "留空=透传，例如 cmd+r、shift+cmd+z、none"
        }

        scrollLinesSlider.numberOfTickMarks = 21
        scrollLinesSlider.allowsTickMarkValuesOnly = true
        scrollLinesSlider.target = self
        scrollLinesSlider.action = #selector(scrollLinesChanged)
        dpiSlider.target = self
        dpiSlider.action = #selector(dpiChanged)
        scrollLinesValue.alignment = .right
        dpiValue.alignment = .right

        dpiRange.textColor = .secondaryLabelColor
        dpiRange.font = .systemFont(ofSize: 11)
        let help = NSTextField(wrappingLabelWithString: "滚动行数 0 表示跟随 macOS。DPI 滑杆按设备实际支持档位映射；MouseBridge 退出后不会继续维持软件设置。")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)

        let save = NSButton(title: "保存并应用", target: self, action: #selector(saveConfig))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        for label in [connectionLabel, inputStatusLabel, permissionStatusLabel] {
            label.font = .systemFont(ofSize: 13, weight: .medium)
        }
        inputStatusLabel.textColor = .systemOrange
        permissionStatusLabel.textColor = .systemOrange
        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)
        let accessibilitySettings = NSButton(title: "辅助功能设置", target: self, action: #selector(openAccessibilitySettings))
        let inputSettings = NSButton(title: "输入监控设置", target: self, action: #selector(openInputMonitoringSettings))
        let permissionButtons = NSStackView(views: [accessibilitySettings, inputSettings])
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 8
        messageLabel.textColor = .systemRed

        let stack = NSStackView(views: [
            title, subtitle, connectionLabel, permissionStatusLabel, inputStatusLabel, permissionButtons,
            grid,
            sliderRow(title: "滚动行数", slider: scrollLinesSlider, value: scrollLinesValue),
            reverseVertical, reverseHorizontal,
            sliderRow(title: "DPI", slider: dpiSlider, value: dpiValue),
            dpiRange, launchAtLogin, help, messageLabel, save,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openPrivacySettings("Privacy_ListenEvent")
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLoginController.setEnabled(launchAtLogin.state == .on)
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            messageLabel.textColor = .systemRed
            messageLabel.stringValue = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    private func refreshLaunchAtLogin() {
        switch LaunchAtLoginController.status {
        case .enabled:
            launchAtLogin.isEnabled = true
            launchAtLogin.state = .on
            launchAtLogin.title = "登录时自动启动"
        case .requiresApproval:
            launchAtLogin.isEnabled = true
            launchAtLogin.state = .on
            launchAtLogin.title = "登录时自动启动（等待系统批准）"
        case .disabled:
            launchAtLogin.isEnabled = true
            launchAtLogin.state = .off
            launchAtLogin.title = "登录时自动启动"
        case .unavailable:
            launchAtLogin.isEnabled = false
            launchAtLogin.state = .off
            launchAtLogin.title = "登录时自动启动（当前系统不可用）"
        }
    }

    private func sliderRow(title: String, slider: NSSlider, value: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.alignment = .right
        titleLabel.widthAnchor.constraint(equalToConstant: 90).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        value.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let row = NSStackView(views: [titleLabel, slider, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func loadConfig() {
        let config = ConfigStore.shared.config
        middleField.stringValue = config.middleAction
        backField.stringValue = config.backAction
        forwardField.stringValue = config.forwardAction
        reverseVertical.state = config.reverseVerticalScroll ? .on : .off
        reverseHorizontal.state = config.reverseHorizontalScroll ? .on : .off
        scrollLinesSlider.integerValue = config.scrollLines
        dpiSlider.doubleValue = percent(forDPI: config.primaryDPI)
        updateScrollLinesValue()
        updateDPIValue()
    }

    private func percent(forDPI dpi: Int) -> Double {
        guard dpiValues.count > 1 else { return 0 }
        let index = dpiValues.indices.min(by: { abs(dpiValues[$0] - dpi) < abs(dpiValues[$1] - dpi) }) ?? 0
        return Double(index) * 100 / Double(dpiValues.count - 1)
    }

    private func dpiForCurrentPercent() -> Int {
        guard dpiValues.count > 1 else { return dpiValues.first ?? 1000 }
        let index = Int((dpiSlider.doubleValue / 100 * Double(dpiValues.count - 1)).rounded())
        return dpiValues[min(dpiValues.count - 1, max(0, index))]
    }

    @objc private func scrollLinesChanged() { updateScrollLinesValue() }
    @objc private func dpiChanged() { updateDPIValue() }

    private func updateScrollLinesValue() {
        scrollLinesValue.stringValue = scrollLinesSlider.integerValue == 0 ? "跟随系统" : "\(scrollLinesSlider.integerValue) 行"
    }

    private func updateDPIValue() {
        dpiValue.stringValue = "\(dpiForCurrentPercent()) DPI · \(Int(dpiSlider.doubleValue.rounded()))%"
    }

    @objc private func saveConfig() {
        window?.makeFirstResponder(nil)
        let actions = [middleField, backField, forwardField].map(\.stringValue)
        guard actions.allSatisfy(ShortcutExecutor.isValid) else {
            messageLabel.textColor = .systemRed
            messageLabel.stringValue = "快捷键格式无效，请使用 cmd+r 这样的格式。"
            return
        }
        var config = ConfigStore.shared.config
        config.middleAction = middleField.stringValue
        config.backAction = backField.stringValue
        config.forwardAction = forwardField.stringValue
        config.reverseVerticalScroll = reverseVertical.state == .on
        config.reverseHorizontalScroll = reverseHorizontal.state == .on
        config.scrollLines = scrollLinesSlider.integerValue
        config.primaryDPI = dpiForCurrentPercent()
        config.normalize()
        do {
            try ConfigStore.shared.save(config)
            loadConfig()
            messageLabel.textColor = .systemGreen
            messageLabel.stringValue = "已保存并应用"
        } catch {
            messageLabel.textColor = .systemRed
            messageLabel.stringValue = error.localizedDescription
        }
    }
}
