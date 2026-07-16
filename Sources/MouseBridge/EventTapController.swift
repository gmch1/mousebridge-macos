// SPDX-License-Identifier: GPL-3.0-or-later
// Scroll-event handling includes adaptations informed by Scroll Reverser,
// Copyright 2011 Nicholas Moore, licensed under Apache-2.0. See LICENSES/.
// Modified and reimplemented for MouseBridge in 2026.

import ApplicationServices
import AppKit
import Darwin
import Foundation

final class EventTapController {
    private static let probeMarker: Int64 = 0x4D425052
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var configProvider: () -> AppConfig
    private var enabledProvider: () -> Bool
    private var trackpadClickHandler: () -> Bool
    private var lastTouchTime = -Double.greatestFiniteMagnitude
    private var touchingCount = 0
    private var lastScrollWasMouse = true
    private var scrollEventCount = 0
    private var buttonEventCount = 0
    private var probeScheduled = false
    private var probeReceived = false
    var onActivity: ((Int, Int) -> Void)?

    init(
        configProvider: @escaping () -> AppConfig,
        enabledProvider: @escaping () -> Bool,
        trackpadClickHandler: @escaping () -> Bool = { false }
    ) {
        self.configProvider = configProvider
        self.enabledProvider = enabledProvider
        self.trackpadClickHandler = trackpadClickHandler
    }

    func start(monitorGestures: Bool) -> Bool {
        if tap != nil {
            if monitorGestures && gestureTap == nil { startGestureTap() }
            DiagnosticLog.shared.write("active event tap already exists")
            return true
        }
        var mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        if DiagnosticLog.verboseEvents {
            mask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: context
        ) else {
            DiagnosticLog.shared.write("active event tap creation FAILED")
            return false
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        DiagnosticLog.shared.write("active event tap created mask=\(mask)")
        DiagnosticLog.shared.write("scroll IOHID SPI available=\(ScrollEventSPI.shared.isAvailable)")

        if monitorGestures { startGestureTap() }
        if DiagnosticLog.verboseEvents { scheduleSelfProbe() }
        return true
    }

    private func scheduleSelfProbe() {
        guard !probeScheduled else { return }
        probeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            guard let probe = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: 1,
                wheel2: 0,
                wheel3: 0
            ) else {
                DiagnosticLog.shared.write("self probe event creation FAILED")
                return
            }
            probe.setIntegerValueField(.eventSourceUserData, value: Self.probeMarker)
            DiagnosticLog.shared.write("self probe posting")
            probe.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                DiagnosticLog.shared.write("self probe result received=\(self?.probeReceived ?? false)")
            }
        }
    }

    private func startGestureTap() {
        guard gestureTap == nil else { return }
        let gestureMask = CGEventMask(1 << NSEvent.EventType.gesture.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        gestureTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: gestureMask,
            callback: eventTapCallback,
            userInfo: context
        )
        if let gestureTap {
            gestureSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gestureTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), gestureSource, .commonModes)
            CGEvent.tapEnable(tap: gestureTap, enable: true)
            DiagnosticLog.shared.write("gesture event tap created")
        } else {
            DiagnosticLog.shared.write("gesture event tap creation FAILED")
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let gestureTap { CGEvent.tapEnable(tap: gestureTap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let gestureSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes) }
        tap = nil
        source = nil
        gestureTap = nil
        gestureSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.probeMarker {
            probeReceived = true
            DiagnosticLog.shared.writeEvent("self probe callback type=\(type.rawValue)")
            return nil
        }
        if type.rawValue == UInt32.max - 1 || type.rawValue == UInt32.max {
            DiagnosticLog.shared.write("event tap disabled callback type=\(type.rawValue); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard enabledProvider() else { return Unmanaged.passUnretained(event) }
        let config = configProvider()

        if type == .leftMouseDown || type == .rightMouseDown {
            if trackpadClickHandler() {
                DiagnosticLog.shared.writeEvent("trackpad physical click gesture triggered")
            }
            // Preserve the physical click. The configured shortcut is an
            // additional action, matching TapBind's behavior.
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == UInt32(NSEvent.EventType.gesture.rawValue) {
            if let nsEvent = NSEvent(cgEvent: event) {
                let count = nsEvent.touches(matching: .touching, in: nil).count
                if count >= 2 {
                    touchingCount = max(touchingCount, count)
                    lastTouchTime = ProcessInfo.processInfo.systemUptime
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            scrollEventCount += 1
            reportActivity()
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let now = ProcessInfo.processInfo.systemUptime
            let touchElapsed = now - lastTouchTime
            let touches = touchingCount
            touchingCount = 0
            let phase = NSEvent(cgEvent: event)?.momentumPhase ?? []
            let isMouse: Bool
            if gestureTap == nil {
                // M750 produces discrete wheel events. Without Input Monitoring,
                // leave continuous trackpad/Magic Mouse events untouched.
                isMouse = !continuous
            } else if !continuous {
                isMouse = true
            } else if touches >= 2 && touchElapsed < 0.222 {
                isMouse = false
            } else if phase.isEmpty && touchElapsed > 0.333 {
                isMouse = true
            } else {
                isMouse = lastScrollWasMouse
            }
            lastScrollWasMouse = isMouse
            DiagnosticLog.shared.writeEvent(
                "scroll #\(scrollEventCount) continuous=\(continuous) isMouse=\(isMouse) phase=\(phase.rawValue) " +
                "axis1=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) " +
                "point1=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) " +
                "fixed1=\(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)) " +
                "reverseV=\(config.reverseVerticalScroll) reverseH=\(config.reverseHorizontalScroll)"
            )
            if isMouse { transformScrollInPlace(event, config: config, continuous: continuous) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp {
            if event.getIntegerValueField(.eventSourceUserData) == ShortcutExecutor.injectedMarker {
                DiagnosticLog.shared.writeEvent(
                    "shortcut observed type=\(type.rawValue) keyCode=\(event.getIntegerValueField(.keyboardEventKeycode)) flags=\(event.flags.rawValue)"
                )
            }
            return Unmanaged.passUnretained(event)
        }

        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        if type == .otherMouseDown {
            buttonEventCount += 1
            reportActivity()
        }
        let action: String
        switch button {
        case 2: action = config.middleAction
        case 3: action = config.backAction
        case 4: action = config.forwardAction
        default: return Unmanaged.passUnretained(event)
        }
        DiagnosticLog.shared.writeEvent("mouse button type=\(type.rawValue) button=\(button) action=\(action.isEmpty ? "<passthrough>" : action)")
        guard !action.isEmpty else { return Unmanaged.passUnretained(event) }
        if type == .otherMouseDown { ShortcutExecutor.execute(action) }
        return nil
    }

    private func transformScrollInPlace(_ event: CGEvent, config: AppConfig, continuous: Bool) {
        guard config.reverseVerticalScroll || config.reverseHorizontalScroll || config.scrollLines > 0 else { return }
        let spi = ScrollEventSPI.shared
        let hidEvent = (config.reverseVerticalScroll || config.reverseHorizontalScroll) ? spi.copyHIDEvent(from: event) : nil
        defer { if let hidEvent { spi.releaseHIDEvent(hidEvent) } }
        let beforeAxis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let beforePoint1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let beforeFixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let beforeAxis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let beforePoint2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let beforeFixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let beforeHIDY = hidEvent.flatMap { spi.floatValue($0, field: ioHIDEventFieldScrollY) }
        let beforeHIDX = hidEvent.flatMap { spi.floatValue($0, field: ioHIDEventFieldScrollX) }
        let vertical = ScrollTransform.vertical(
            axis: beforeAxis1,
            point: beforePoint1,
            fixed: beforeFixed1,
            continuous: continuous,
            reverse: config.reverseVerticalScroll,
            lines: config.scrollLines
        )
        if let vertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: vertical.axis)
            if let fixed = vertical.fixed {
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed)
            }
            if let point = vertical.point {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point)
            }
            if !vertical.adjustsDiscreteStep, let hidEvent {
                spi.setFloatValue(hidEvent, field: ioHIDEventFieldScrollY, value: -(beforeHIDY ?? 0))
            }
        }
        if config.reverseHorizontalScroll {
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis2,
                value: -beforeAxis2
            )
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis2,
                value: -beforeFixed2
            )
            event.setIntegerValueField(
                .scrollWheelEventPointDeltaAxis2,
                value: -beforePoint2
            )
            if let hidEvent {
                spi.setFloatValue(hidEvent, field: ioHIDEventFieldScrollX, value: -(beforeHIDX ?? 0))
            }
        }
        let afterHIDY = hidEvent.flatMap { spi.floatValue($0, field: ioHIDEventFieldScrollY) }
        DiagnosticLog.shared.writeEvent(
            "scroll transformed hid=\(hidEvent != nil) " +
            "axis1=\(beforeAxis1)->\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) " +
            "point1=\(beforePoint1)->\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) " +
            "fixed1=\(beforeFixed1)->\(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)) " +
            "hidY=\(beforeHIDY.map { String($0) } ?? "nil")->\(afterHIDY.map { String($0) } ?? "nil") " +
            "scrollLines=\(config.scrollLines) discreteAdjusted=\(vertical?.adjustsDiscreteStep ?? false)"
        )
    }

    private func reportActivity() {
        guard DiagnosticLog.verboseEvents else { return }
        let scrolls = scrollEventCount
        let buttons = buttonEventCount
        DispatchQueue.main.async { [weak self] in self?.onActivity?(scrolls, buttons) }
    }
}

// Scroll Reverser also updates the IOHID payload underneath CGEvent. These SPI
// symbols are present in macOS but are not part of the public SDK.
private let ioHIDEventFieldScrollX: UInt32 = UInt32(6 << 16)
private let ioHIDEventFieldScrollY: UInt32 = UInt32(6 << 16) | 1

private final class ScrollEventSPI {
    typealias CopyHIDEvent = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias GetFloatValue = @convention(c) (UnsafeRawPointer?, UInt32) -> Double
    typealias SetFloatValue = @convention(c) (UnsafeMutableRawPointer?, UInt32, Double) -> Void

    static let shared = ScrollEventSPI()

    private let coreGraphicsHandle: UnsafeMutableRawPointer?
    private let ioKitHandle: UnsafeMutableRawPointer?
    private let copyFunction: CopyHIDEvent?
    private let getFunction: GetFloatValue?
    private let setFunction: SetFloatValue?

    private init() {
        coreGraphicsHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL)
        ioKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
        if let symbol = coreGraphicsHandle.flatMap({ dlsym($0, "CGEventCopyIOHIDEvent") }) {
            copyFunction = unsafeBitCast(symbol, to: CopyHIDEvent.self)
        } else {
            copyFunction = nil
        }
        if let symbol = ioKitHandle.flatMap({ dlsym($0, "IOHIDEventGetFloatValue") }) {
            getFunction = unsafeBitCast(symbol, to: GetFloatValue.self)
        } else {
            getFunction = nil
        }
        if let symbol = ioKitHandle.flatMap({ dlsym($0, "IOHIDEventSetFloatValue") }) {
            setFunction = unsafeBitCast(symbol, to: SetFloatValue.self)
        } else {
            setFunction = nil
        }
    }

    var isAvailable: Bool { copyFunction != nil && getFunction != nil && setFunction != nil }

    func copyHIDEvent(from event: CGEvent) -> UnsafeMutableRawPointer? {
        guard isAvailable else { return nil }
        return copyFunction?(Unmanaged.passUnretained(event).toOpaque())
    }

    func releaseHIDEvent(_ event: UnsafeMutableRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(event).release()
    }

    func floatValue(_ event: UnsafeRawPointer, field: UInt32) -> Double? {
        getFunction?(event, field)
    }

    func setFloatValue(_ event: UnsafeMutableRawPointer, field: UInt32, value: Double) {
        setFunction?(event, field, value)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
