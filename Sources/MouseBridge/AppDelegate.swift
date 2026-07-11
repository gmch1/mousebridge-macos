// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController!
    private let hid = HIDPPController()
    private var eventTap: EventTapController!
    private var config = AppConfig()
    private var isEnabled = true
    private var connectionItem: NSMenuItem!
    private var inputStatusItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var permissionTimer: Timer?
    private var lastLoggedPermissions: (Bool, Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.shared.resetForLaunch()
        config = ConfigStore.shared.config
        ConfigStore.shared.startWatching()
        DiagnosticLog.shared.write("launch bundle=\(Bundle.main.bundlePath) pid=\(ProcessInfo.processInfo.processIdentifier)")
        DiagnosticLog.shared.write("config back=\(config.backAction) forward=\(config.forwardAction) middle=\(config.middleAction) reverseV=\(config.reverseVerticalScroll) reverseH=\(config.reverseHorizontalScroll) scrollLines=\(config.scrollLines) dpi=\(config.primaryDPI)")
        buildStatusMenu()
        settingsWindow = SettingsWindowController()

        eventTap = EventTapController(
            configProvider: { [weak self] in self?.config ?? AppConfig() },
            enabledProvider: { [weak self] in self?.isEnabled ?? false }
        )
        eventTap.onActivity = { [weak self] scrolls, buttons in
            self?.setInputStatus("按键与滚轮：运行中（滚轮 \(scrolls)，按键 \(buttons)）", ready: true)
        }
        startInputMonitoringWhenAuthorized(prompt: true)

        hid.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            DiagnosticLog.shared.write("hid connection changed connected=\(connected)")
            self.connectionItem.title = connected ? "M750：已连接" : "M750：未连接"
            self.settingsWindow.setConnected(connected)
            if connected {
                self.hid.setDPI(self.config.primaryDPI) { success in
                    if !success { DiagnosticLog.shared.write("initial DPI apply FAILED value=\(self.config.primaryDPI)") }
                }
            }
        }
        hid.onDPICapabilities = { [weak self] capabilities in
            self?.settingsWindow.setDPICapabilities(capabilities)
        }
        hid.start()

        NotificationCenter.default.addObserver(
            forName: ConfigStore.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let updated = notification.object as? AppConfig else { return }
            Task { @MainActor in
                self.config = updated
                DiagnosticLog.shared.write("config changed back=\(updated.backAction) forward=\(updated.forwardAction) middle=\(updated.middleAction) reverseV=\(updated.reverseVerticalScroll) reverseH=\(updated.reverseHorizontalScroll) scrollLines=\(updated.scrollLines) dpi=\(updated.primaryDPI)")
                self.hid.setDPI(updated.primaryDPI) { success in
                    if !success { DiagnosticLog.shared.write("apply configured DPI FAILED value=\(updated.primaryDPI)") }
                    DispatchQueue.main.async { [weak self] in
                        self?.settingsWindow.setDPIApplyResult(success, value: updated.primaryDPI)
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConfigStore.shared.stopWatching()
        permissionTimer?.invalidate()
        eventTap?.stop()
        hid.stop()
    }

    private func startInputMonitoringWhenAuthorized(prompt: Bool) {
        let accessibilityGranted = AXIsProcessTrusted()
        let inputMonitoringGranted = CGPreflightListenEventAccess()
        if lastLoggedPermissions?.0 != accessibilityGranted || lastLoggedPermissions?.1 != inputMonitoringGranted {
            DiagnosticLog.shared.write("permissions accessibility=\(accessibilityGranted) inputMonitoring=\(inputMonitoringGranted)")
            lastLoggedPermissions = (accessibilityGranted, inputMonitoringGranted)
        }
        settingsWindow?.setPermissionStatus(
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted
        )

        if accessibilityGranted {
            let started = eventTap.start(monitorGestures: inputMonitoringGranted)
            DiagnosticLog.shared.write("event tap requested gestures=\(inputMonitoringGranted) started=\(started)")
            let suffix = inputMonitoringGranted ? "" : "（M750 模式）"
            setInputStatus(started ? "按键与滚轮：运行中\(suffix)" : "按键与滚轮：启动失败", ready: started)
            if inputMonitoringGranted {
                permissionTimer?.invalidate()
                permissionTimer = nil
            } else {
                schedulePermissionRefresh()
                requestMissingPermissions(
                    accessibilityGranted: true,
                    inputMonitoringGranted: false,
                    prompt: prompt
                )
            }
            return
        }

        var missing: [String] = []
        if !accessibilityGranted { missing.append("辅助功能") }
        if !inputMonitoringGranted { missing.append("输入监控") }
        setInputStatus("按键与滚轮：等待\(missing.joined(separator: "、"))权限", ready: false)
        requestMissingPermissions(
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted,
            prompt: prompt
        )
        schedulePermissionRefresh()
    }

    private func requestMissingPermissions(
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        prompt: Bool
    ) {
        guard prompt else { return }
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !inputMonitoringGranted && !UserDefaults.standard.bool(forKey: "hasRequestedInputMonitoring") {
            UserDefaults.standard.set(true, forKey: "hasRequestedInputMonitoring")
            DispatchQueue.global(qos: .userInitiated).async {
                _ = CGRequestListenEventAccess()
            }
        }
    }

    private func schedulePermissionRefresh() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.startInputMonitoringWhenAuthorized(prompt: false) }
        }
    }

    private func setInputStatus(_ text: String, ready: Bool) {
        inputStatusItem.title = text
        settingsWindow?.setInputStatus(text, ready: ready)
    }

    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseBridge")
        }
        let menu = NSMenu()
        connectionItem = NSMenuItem(title: "M750：正在连接…", action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        inputStatusItem = NSMenuItem(title: "按键与滚轮：检查权限…", action: nil, keyEquivalent: "")
        inputStatusItem.isEnabled = false
        menu.addItem(inputStatusItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: ","))
        toggleItem = NSMenuItem(title: "暂停映射", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "关于 MouseBridge…", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 MouseBridge", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        settingsWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        toggleItem.title = isEnabled ? "暂停映射" : "恢复映射"
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let alert = NSAlert()
        alert.messageText = "MouseBridge \(version)"
        alert.informativeText = """
        Copyright © 2026 guomingchao 与 MouseBridge 贡献者

        本程序是使用 GPL-3.0-or-later 分发的自由软件，不提供任何担保。你可以依照许可证复制、修改和再分发。完整许可证与第三方声明位于应用包 Contents/Resources/Legal，源码可从 GitHub 免费获取。
        """
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "查看源码")
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/gmch1/mousebridge-macos") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}
