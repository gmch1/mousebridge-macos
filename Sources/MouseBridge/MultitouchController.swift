// SPDX-License-Identifier: GPL-3.0-or-later
// Private MultitouchSupport integration adapted from TapBind / MiddleClick.

import Foundation
import IOKit
import MultitouchSupport

@_silgen_name("MTDeviceCreateList")
private func MTDeviceCreateList() -> Unmanaged<CFMutableArray>?

final class MultitouchController {
    enum Trigger: String {
        case physicalClick = "physical-click"
        case tap
    }

    typealias TriggerHandler = (_ action: String, _ trigger: Trigger) -> Void

    static let shared = MultitouchController()
    private static let contactFrameCallback: MTFrameCallbackFunction = { _, data, count, timestamp, _ in
        MultitouchController.shared.handleFrame(data: data, count: Int(count), timestamp: timestamp)
    }

    private let stateLock = NSLock()
    private var triggerHandler: TriggerHandler?
    private var config = AppConfig()
    private var appEnabled = true
    private var recognizer: MultitouchGestureRecognizer
    private var currentDevices: [MTDevice] = []
    private var notificationPort: IONotificationPortRef?
    private var deviceIterator: io_iterator_t = 0
    private var refreshWorkItem: DispatchWorkItem?
    private var running = false

    private init() {
        recognizer = MultitouchGestureRecognizer(
            settings: MultitouchController.settings(config: AppConfig(), appEnabled: true)
        )
    }

    func configure(config: AppConfig, triggerHandler: @escaping TriggerHandler) {
        stateLock.lock()
        self.config = config
        self.triggerHandler = triggerHandler
        recognizer.update(settings: Self.settings(config: config, appEnabled: appEnabled))
        stateLock.unlock()
        requestListeningStateUpdate()
    }

    func start() {
        guard !running else { return }
        running = true
        updateListeningState()
    }

    func stop() {
        guard running else { return }
        running = false
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        stopDeviceNotifications()
        unregisterCurrentDevices()
    }

    func updateConfig(_ newConfig: AppConfig) {
        stateLock.lock()
        config = newConfig
        recognizer.update(settings: Self.settings(config: newConfig, appEnabled: appEnabled))
        stateLock.unlock()
        requestListeningStateUpdate()
    }

    func setAppEnabled(_ enabled: Bool) {
        stateLock.lock()
        appEnabled = enabled
        recognizer.update(settings: Self.settings(config: config, appEnabled: enabled))
        stateLock.unlock()
        requestListeningStateUpdate()
    }

    /// Called by the active Quartz event tap for left/right physical clicks.
    /// The original click is deliberately passed through, matching TapBind.
    @discardableResult
    func handlePhysicalClick() -> Bool {
        stateLock.lock()
        let triggered = recognizer.consumePhysicalClickIfArmed()
        let action = config.trackpadAction
        stateLock.unlock()
        if triggered { emit(action: action, trigger: .physicalClick) }
        return triggered
    }

    private func handleFrame(data: UnsafePointer<MTTouch>?, count: Int, timestamp: TimeInterval) {
        stateLock.lock()
        let targetCount = config.trackpadFingerCount
        var aggregate: TrackpadTouchPoint?
        if let data, count >= targetCount {
            var x = 0.0
            var y = 0.0
            for index in 0..<targetCount {
                x += Double(data[index].normalizedVector.position.x)
                y += Double(data[index].normalizedVector.position.y)
            }
            aggregate = TrackpadTouchPoint(x: x, y: y)
        }
        let triggered = recognizer.processFrame(
            fingerCount: count,
            aggregatePosition: aggregate,
            timestamp: timestamp
        )
        let action = config.trackpadAction
        stateLock.unlock()
        if triggered { emit(action: action, trigger: .tap) }
    }

    private func emit(action: String, trigger: Trigger) {
        stateLock.lock()
        let handler = triggerHandler
        stateLock.unlock()
        DispatchQueue.main.async {
            handler?(action, trigger)
        }
    }

    private static func settings(config: AppConfig, appEnabled: Bool) -> MultitouchGestureRecognizer.Settings {
        MultitouchGestureRecognizer.Settings(
            enabled: appEnabled && config.trackpadGestureEnabled,
            fingerCount: config.trackpadFingerCount,
            tapEnabled: config.trackpadTapEnabled,
            allowMoreFingers: config.trackpadAllowMoreFingers,
            maximumTapDuration: Double(config.trackpadTapMaxMilliseconds) / 1_000,
            maximumTapMovement: config.trackpadTapMaxMovement
        )
    }

    private func refreshDevices() {
        guard running, isListeningEnabled else { return }
        unregisterCurrentDevices()
        currentDevices = MTDevice.createList()
        currentDevices.forEach { $0.registerAndStart(Self.contactFrameCallback) }
        DiagnosticLog.shared.write("multitouch devices registered count=\(currentDevices.count)")
    }

    private var isListeningEnabled: Bool {
        stateLock.lock()
        let enabled = appEnabled && config.trackpadGestureEnabled
        stateLock.unlock()
        return enabled
    }

    private func requestListeningStateUpdate() {
        if Thread.isMainThread {
            updateListeningState()
        } else {
            DispatchQueue.main.async { [weak self] in self?.updateListeningState() }
        }
    }

    private func updateListeningState() {
        guard running else { return }
        if isListeningEnabled {
            startDeviceNotifications()
            if currentDevices.isEmpty { refreshDevices() }
        } else {
            refreshWorkItem?.cancel()
            refreshWorkItem = nil
            stopDeviceNotifications()
            unregisterCurrentDevices()
            DiagnosticLog.shared.write("multitouch listener inactive")
        }
    }

    private func unregisterCurrentDevices() {
        currentDevices.forEach { $0.unregisterAndStop(Self.contactFrameCallback) }
        currentDevices.removeAll()
    }

    private func startDeviceNotifications() {
        guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("AppleMultitouchDevice"),
            multitouchDeviceMatchedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &deviceIterator
        )
        guard result == KERN_SUCCESS else {
            DiagnosticLog.shared.write("multitouch device notification registration FAILED result=\(result)")
            stopDeviceNotifications()
            return
        }
        drain(iterator: deviceIterator)
    }

    private func stopDeviceNotifications() {
        if deviceIterator != 0 {
            IOObjectRelease(deviceIterator)
            deviceIterator = 0
        }
        if let notificationPort {
            let source = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
    }

    fileprivate func handleDeviceMatched(iterator: io_iterator_t) {
        drain(iterator: iterator)
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshDevices() }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func drain(iterator: io_iterator_t) {
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            IOObjectRelease(service)
        }
    }
}

private let multitouchDeviceMatchedCallback: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<MultitouchController>.fromOpaque(context)
        .takeUnretainedValue()
        .handleDeviceMatched(iterator: iterator)
}

private extension MTDevice {
    func registerAndStart(_ callback: MTFrameCallbackFunction) {
        register(contactFrameCallback: callback)
        start(runMode: 0)
    }

    func unregisterAndStop(_ callback: MTFrameCallbackFunction) {
        unregister(contactFrameCallback: callback)
        stop()
        release()
    }

    static func createList() -> [MTDevice] {
        MTDeviceCreateList()?.takeUnretainedValue() as? [MTDevice] ?? []
    }
}
