// SPDX-License-Identifier: GPL-3.0-or-later
// HID++ adjustable-DPI list decoding is adapted from Solaar,
// Copyright 2012-2013 Daniel Pavel and Solaar contributors,
// originally licensed under GPL-2.0-or-later. See LICENSES/.
// Modified and reimplemented for MouseBridge in 2026.

import Foundation
import IOKit.hid

struct MouseDeviceProfile: Sendable {
    let name: String
    let vendorID: Int
    let productIDs: Set<Int>
    let usagePage: Int
    let usage: Int

    static let m750Bluetooth = MouseDeviceProfile(
        name: "Logitech Signature Plus M750 L",
        vendorID: 0x046D,
        productIDs: [0xB02C],
        usagePage: 1,
        usage: 2
    )

    var matchingDictionaries: [[String: Any]] {
        productIDs.map {
            [
                kIOHIDVendorIDKey as String: vendorID,
                kIOHIDProductIDKey as String: $0,
                kIOHIDPrimaryUsagePageKey as String: usagePage,
                kIOHIDPrimaryUsageKey as String: usage,
            ]
        }
    }
}

final class HIDPPController {
    struct DPICapabilities: Sendable {
        let values: [Int]
        let cameFromDevice: Bool
        var minimum: Int { values.first ?? 400 }
        var maximum: Int { values.last ?? 4000 }
    }

    private static let longReportID: UInt8 = 0x11
    private static let softwareID: UInt8 = 0x0A

    var onConnectionChanged: ((Bool) -> Void)?
    var onDPICapabilities: ((DPICapabilities) -> Void)?

    private let profile: MouseDeviceProfile
    private let requestQueue = DispatchQueue(label: "mousebridge.hidpp.requests")
    private let stateLock = NSLock()
    private let requestLock = NSLock()
    private let pendingLock = NSLock()
    private let stopped = DispatchSemaphore(value: 0)

    // Device lifecycle state is created and destroyed on the HID run-loop
    // thread. Other threads may only take retained snapshots under stateLock.
    private var runLoopThread: Thread?
    private var hidRunLoop: CFRunLoop?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var dpiFeature: UInt8?
    private var supportedDPIs: [Int] = []
    private var originalDPI: Int?
    private var running = false
    private var stopping = false
    private var pending: PendingRequest?

    private final class PendingRequest {
        let feature: UInt8
        let function: UInt8
        let semaphore = DispatchSemaphore(value: 0)
        var response: Message?

        init(feature: UInt8, function: UInt8) {
            self.feature = feature
            self.function = function
        }
    }

    struct Message: Sendable {
        let deviceIndex: UInt8
        let feature: UInt8
        let function: UInt8
        let softwareID: UInt8
        let parameters: [UInt8]
    }

    init(profile: MouseDeviceProfile = .m750Bluetooth) {
        self.profile = profile
    }

    func start() {
        stateLock.lock()
        guard !running else {
            stateLock.unlock()
            return
        }
        running = true
        stopping = false
        stateLock.unlock()

        let thread = Thread { [weak self] in self?.runHIDLoop() }
        thread.name = "MouseBridge-HIDRunLoop"
        runLoopThread = thread
        thread.start()
    }

    /// Restores the DPI observed at connection time, then shuts down the HID
    /// run loop. A force-quit cannot restore device state.
    func stop() {
        stateLock.lock()
        guard running, !stopping else {
            stateLock.unlock()
            return
        }
        stopping = true
        let feature = dpiFeature
        let dpi = originalDPI
        let runLoop = hidRunLoop
        stateLock.unlock()

        if let feature, let dpi {
            let restored = sendDPI(feature: feature, value: dpi, allowWhileStopping: true)
            DiagnosticLog.shared.write("dpi restore value=\(dpi) success=\(restored)")
        }

        guard let runLoop else {
            stateLock.lock()
            running = false
            stateLock.unlock()
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            guard let self else { return }
            self.cleanupDeviceOnHIDThread()
            if let manager = self.manager {
                IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                self.manager = nil
            }
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        _ = stopped.wait(timeout: .now() + 3)
    }

    func setDPI(_ value: Int, completion: ((Bool) -> Void)? = nil) {
        requestQueue.async { [weak self] in
            guard let self else {
                completion?(false)
                return
            }
            self.stateLock.lock()
            let feature = self.dpiFeature
            let supported = self.supportedDPIs
            let stopping = self.stopping
            self.stateLock.unlock()
            guard let feature, !stopping else {
                completion?(false)
                return
            }
            let requested = AppConfig.clampDPI(value)
            let dpi = supported.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? requested
            completion?(self.sendDPI(feature: feature, value: dpi))
        }
    }

    func readDPI(completion: @escaping (Int?) -> Void) {
        requestQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.stateLock.lock()
            let feature = self.dpiFeature
            self.stateLock.unlock()
            completion(feature.flatMap { self.readDPIValue(feature: $0) })
        }
    }

    private func runHIDLoop() {
        autoreleasepool {
            guard let runLoop = CFRunLoopGetCurrent() else {
                DiagnosticLog.shared.write("hid run loop creation FAILED")
                stateLock.lock()
                running = false
                stopping = false
                stateLock.unlock()
                stopped.signal()
                return
            }
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            stateLock.lock()
            hidRunLoop = runLoop
            self.manager = manager
            stateLock.unlock()

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerSetDeviceMatchingMultiple(manager, profile.matchingDictionaries as CFArray)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
            IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            DiagnosticLog.shared.write("hid manager open result=\(openResult) profile=\(profile.name)")

            if openResult == kIOReturnSuccess { CFRunLoopRun() }

            cleanupDeviceOnHIDThread()
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            stateLock.lock()
            self.manager = nil
            hidRunLoop = nil
            running = false
            stopping = false
            stateLock.unlock()
            stopped.signal()
        }
    }

    fileprivate func matched(_ candidate: IOHIDDevice) {
        stateLock.lock()
        let canAttach = running && !stopping && device == nil
        stateLock.unlock()
        guard canAttach else { return }
        guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            DiagnosticLog.shared.write("hid device open FAILED")
            return
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
        stateLock.lock()
        device = candidate
        inputBuffer = buffer
        stateLock.unlock()

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(candidate, buffer, 64, inputReportCallback, context)
        IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        requestQueue.async { [weak self, candidate] in self?.configureConnectedDevice(candidate) }
    }

    fileprivate func removed(_ removed: IOHIDDevice) {
        stateLock.lock()
        let isCurrent = device === removed
        stateLock.unlock()
        guard isCurrent else { return }
        cleanupDeviceOnHIDThread()
        notifyConnection(false)
    }

    private func configureConnectedDevice(_ expectedDevice: IOHIDDevice) {
        guard let dpi = findFeature(0x2201) else {
            scheduleCleanup(expectedDevice)
            return
        }
        let deviceDPIs = readSupportedDPIs(feature: dpi)
        let capabilities = DPICapabilities(
            values: deviceDPIs.isEmpty ? Array(stride(from: 400, through: 4000, by: 50)) : deviceDPIs,
            cameFromDevice: !deviceDPIs.isEmpty
        )
        let currentDPI = readDPIValue(feature: dpi)

        stateLock.lock()
        guard device === expectedDevice, !stopping else {
            stateLock.unlock()
            return
        }
        dpiFeature = dpi
        supportedDPIs = capabilities.values
        originalDPI = currentDPI
        stateLock.unlock()

        DiagnosticLog.shared.write(
            "dpi capabilities min=\(capabilities.minimum) max=\(capabilities.maximum) " +
            "count=\(capabilities.values.count) deviceReported=\(capabilities.cameFromDevice) original=\(currentDPI.map(String.init) ?? "unknown")"
        )
        DispatchQueue.main.async { [weak self] in self?.onDPICapabilities?(capabilities) }
        notifyConnection(true)
    }

    private func scheduleCleanup(_ expectedDevice: IOHIDDevice) {
        stateLock.lock()
        let runLoop = hidRunLoop
        stateLock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self, expectedDevice] in
            guard let self else { return }
            self.stateLock.lock()
            let isCurrent = self.device === expectedDevice
            self.stateLock.unlock()
            guard isCurrent else { return }
            self.cleanupDeviceOnHIDThread()
            self.notifyConnection(false)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func cleanupDeviceOnHIDThread() {
        cancelPendingRequest()
        requestLock.lock()
        defer { requestLock.unlock() }

        stateLock.lock()
        let device = self.device
        let buffer = inputBuffer
        self.device = nil
        inputBuffer = nil
        dpiFeature = nil
        supportedDPIs = []
        originalDPI = nil
        stateLock.unlock()

        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        buffer?.deinitialize(count: 64)
        buffer?.deallocate()
    }

    private func sendDPI(feature: UInt8, value: Int, allowWhileStopping: Bool = false) -> Bool {
        let dpi = AppConfig.clampDPI(value)
        return request(
            feature: feature,
            function: 3,
            parameters: [0, UInt8((dpi >> 8) & 0xFF), UInt8(dpi & 0xFF)],
            allowWhileStopping: allowWhileStopping
        ) != nil
    }

    private func readDPIValue(feature: UInt8) -> Int? {
        guard let response = request(feature: feature, function: 2, parameters: [0]),
              response.parameters.count >= 3 else { return nil }
        let current = (Int(response.parameters[1]) << 8) | Int(response.parameters[2])
        if current != 0 { return current }
        guard response.parameters.count >= 5 else { return nil }
        return (Int(response.parameters[3]) << 8) | Int(response.parameters[4])
    }

    private func readSupportedDPIs(feature: UInt8) -> [Int] {
        var bytes: [UInt8] = []
        for page in 0..<16 {
            guard let response = request(feature: feature, function: 1, parameters: [0, 0, UInt8(page)]),
                  response.parameters.count > 1 else { break }
            let payload = Array(response.parameters.dropFirst())
            bytes.append(contentsOf: payload)
            if payload.count >= 2 && payload.suffix(2) == [0, 0] { break }
        }
        return Self.decodeDPIList(bytes)
    }

    static func decodeDPIList(_ bytes: [UInt8]) -> [Int] {
        var values: [Int] = []
        var index = 0
        while index + 1 < bytes.count {
            let value = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
            if value == 0 { break }
            if value >> 13 == 0b111 {
                let step = value & 0x1FFF
                guard step > 0, let previous = values.last, index + 3 < bytes.count else { break }
                let maximum = (Int(bytes[index + 2]) << 8) | Int(bytes[index + 3])
                guard maximum > previous else { break }
                values.append(contentsOf: stride(from: previous + step, through: maximum, by: step))
                index += 4
            } else {
                values.append(value)
                index += 2
            }
        }
        return Array(Set(values.filter { (100...10000).contains($0) })).sorted()
    }

    private func findFeature(_ identifier: UInt16) -> UInt8? {
        let response = request(
            feature: 0,
            function: 0,
            parameters: [UInt8(identifier >> 8), UInt8(identifier & 0xFF), 0]
        )
        return response?.parameters.first.flatMap { $0 == 0 ? nil : $0 }
    }

    private func request(
        feature: UInt8,
        function: UInt8,
        parameters: [UInt8],
        allowWhileStopping: Bool = false
    ) -> Message? {
        requestLock.lock()
        defer { requestLock.unlock() }

        stateLock.lock()
        let device = self.device
        let canRequest = device != nil && (!stopping || allowWhileStopping)
        stateLock.unlock()
        guard canRequest, let device else { return nil }

        let pending = PendingRequest(feature: feature, function: function)
        pendingLock.lock()
        self.pending = pending
        pendingLock.unlock()

        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = Self.longReportID
        bytes[1] = 0xFF
        bytes[2] = feature
        bytes[3] = ((function & 0x0F) << 4) | Self.softwareID
        for (index, value) in parameters.prefix(16).enumerated() { bytes[index + 4] = value }
        let result = bytes.withUnsafeBytes { pointer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(Self.longReportID),
                pointer.bindMemory(to: UInt8.self).baseAddress!,
                bytes.count
            )
        }
        guard result == kIOReturnSuccess else {
            clearPending(pending)
            DiagnosticLog.shared.write("hid request set-report FAILED result=\(result) feature=\(feature) function=\(function)")
            return nil
        }
        guard pending.semaphore.wait(timeout: .now() + 2) == .success else {
            clearPending(pending)
            DiagnosticLog.shared.write("hid request timeout feature=\(feature) function=\(function)")
            return nil
        }
        clearPending(pending)
        return pending.response
    }

    private func clearPending(_ request: PendingRequest) {
        pendingLock.lock()
        if pending === request { pending = nil }
        pendingLock.unlock()
    }

    private func cancelPendingRequest() {
        pendingLock.lock()
        let request = pending
        pending = nil
        pendingLock.unlock()
        request?.semaphore.signal()
    }

    fileprivate func received(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, count: Int) {
        guard count > 0 else { return }
        var data = Array(UnsafeBufferPointer(start: bytes, count: count))
        if data.first != 0x10 && data.first != 0x11 { data.insert(UInt8(reportID & 0xFF), at: 0) }
        guard let message = parse(data) else { return }

        pendingLock.lock()
        let active = pending
        let expectedFunctions = [active?.function, active.map { ($0.function + 1) & 0x0F }].compactMap { $0 }
        if let active,
           message.feature == active.feature,
           message.softwareID == Self.softwareID,
           expectedFunctions.contains(message.function) {
            active.response = message
            pendingLock.unlock()
            active.semaphore.signal()
            return
        }
        pendingLock.unlock()
    }

    private func parse(_ data: [UInt8]) -> Message? {
        guard data.count >= 4 else { return nil }
        let offset = (data[0] == 0x10 || data[0] == 0x11) ? 1 : 0
        guard data.count >= offset + 3 else { return nil }
        let functionAndSoftware = data[offset + 2]
        return Message(
            deviceIndex: data[offset],
            feature: data[offset + 1],
            function: (functionAndSoftware >> 4) & 0x0F,
            softwareID: functionAndSoftware & 0x0F,
            parameters: Array(data.dropFirst(offset + 3))
        )
    }

    private func notifyConnection(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onConnectionChanged?(connected) }
    }
}

private let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDPPController>.fromOpaque(context).takeUnretainedValue().matched(device)
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDPPController>.fromOpaque(context).takeUnretainedValue().removed(device)
}

private let inputReportCallback: IOHIDReportCallback = { context, result, _, _, reportID, report, reportLength in
    guard result == kIOReturnSuccess, let context, reportLength > 0 else { return }
    Unmanaged<HIDPPController>.fromOpaque(context).takeUnretainedValue().received(
        reportID: reportID,
        bytes: report,
        count: reportLength
    )
}
