import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid

/// All input taps for the rebuilt touch engine. Nothing here seizes the USB device.
final class TouchSources {
    var onSample: ((TouchSample) -> Void)?
    var onLog: ((String) -> Void)?
    var onPresence: ((Bool) -> Void)?
    var remapPoint: ((CGPoint) -> CGPoint)?

    private(set) var probeSummary = "starting…"
    private var monitor: UnsafeMutableRawPointer?
    private var matcher: UnsafeMutableRawPointer?
    private var manager: IOHIDManager?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var ctpSender: UInt64 = 0
    private var hidEvents = 0
    private var ctpEvents = 0
    private var tapEvents = 0
    private var lastKinds: [String] = []
    private var senders: [UInt64: Int] = [:]
    private var usbReports = 0
    private var lastUSBBump: TimeInterval = 0
    private var remapped = 0
    private var fingerDown = false
    private var pollDevice: IOHIDDevice?
    private var xEls: [IOHIDElement] = []
    private var yEls: [IOHIDElement] = []
    private var tipEls: [IOHIDElement] = []
    private var countEl: IOHIDElement?
    private var pollX = 0
    private var pollY = 0
    private var pollTip = 0
    private var pollCount = 0
    private var pollOK = false
    private var lastFingerN = 0
    private let lock = NSLock()

    func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in self?.run() }
        t.name = "local.paperlike.touch.v2"
        t.start()
        thread = t
    }

    func stop() {
        if let rl = runLoop { CFRunLoopStop(rl) }
        thread = nil
    }

    private func run() {
        runLoop = CFRunLoopGetCurrent()
        startHIDMonitor()
        startPresenceWatch()
        startEventTap()
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { [weak self] _ in
            self?.tick()
        }
        let poll = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.01, 0.008, 0, 0) { [weak self] _ in
            self?.pollHID()
        }
        if let poll { CFRunLoopAddTimer(CFRunLoopGetCurrent(), poll, .defaultMode) }
        if let timer { CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode) }
        CFRunLoopRun()
        monitor = nil
        matcher = nil
        if let mgr = manager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func startPresenceWatch() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey as String: 0x1A86,
            kIOHIDProductIDKey as String: 0xE5E3,
        ] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        let present = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>)?.isEmpty == false
        onPresence?(present)
        if let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, let device = devices.first {
            bindPollDevice(device)
        }
    }

    private func bindPollDevice(_ device: IOHIDDevice) {
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        pollDevice = device
        guard let raw = IOHIDDeviceCopyMatchingElements(device, nil, 0) else {
            log("no HID elements")
            return
        }
        let elements = raw as! [IOHIDElement]
        for el in elements {
            let page = IOHIDElementGetUsagePage(el)
            let usage = IOHIDElementGetUsage(el)
            if page == 1, usage == 0x30 { xEls.append(el) }
            if page == 1, usage == 0x31 { yEls.append(el) }
            if page == 0x0D, usage == 0x42 { tipEls.append(el) }
            if page == 0x0D, usage == 0x54, countEl == nil { countEl = el }
        }
        log("poll fingers tips=\(tipEls.count) x=\(xEls.count) y=\(yEls.count)")
    }

    private func readElement(_ el: IOHIDElement?) -> Int {
        guard let el, let device = pollDevice else { return 0 }
        let dummy = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, 0, 0)
        var val = Unmanaged<IOHIDValue>.passUnretained(dummy)
        let kr = IOHIDDeviceGetValue(device, el, &val)
        guard kr == kIOReturnSuccess else { return 0 }
        pollOK = true
        return Int(IOHIDValueGetIntegerValue(val.takeUnretainedValue()))
    }

    private func pollHID() {
        let n = min(tipEls.count, min(xEls.count, yEls.count))
        var fingers: [TouchFinger] = []
        fingers.reserveCapacity(n)
        for i in 0..<n {
            let tip = readElement(tipEls[i])
            guard tip != 0 else { continue }
            let x = readElement(xEls[i])
            let y = readElement(yEls[i])
            let (nx, ny) = normalize(Double(x), Double(y))
            fingers.append(TouchFinger(nx: nx, ny: ny, id: i))
        }
        pollTip = fingers.isEmpty ? 0 : 1
        pollCount = fingers.count
        if let first = fingers.first {
            pollX = Int((first.nx * 4096).rounded())
            pollY = Int((first.ny * 4096).rounded())
        }
        let down = !fingers.isEmpty
        let changed = down != fingerDown || fingers.count != lastFingerN
        fingerDown = down
        lastFingerN = fingers.count
        guard down || changed else { return }
        onSample?(TouchSample(
            fingers: fingers,
            summary: "fingers=\(fingers.count) x=\(pollX) y=\(pollY)"
        ))
    }

    private func startHIDMonitor() {
        guard let create = API.createWithType else {
            log("HID Monitor API missing")
            return
        }
        if let m = create(kCFAllocatorDefault, 1, nil) {
            matcher = m
            API.setMatching?(m, [
                kIOHIDVendorIDKey as String: 0x1A86,
                kIOHIDProductIDKey as String: 0xE5E3,
            ] as CFDictionary)
            API.schedule?(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            ctpSender = readSender(m)
        }
        guard let mon = create(kCFAllocatorDefault, 1, nil) else { return }
        monitor = mon
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        API.register?(mon, { _, refcon, _, event in
            guard let refcon, let event else { return }
            Unmanaged<TouchSources>.fromOpaque(refcon).takeUnretainedValue().gotHIDEvent(event)
        }, nil, ctx)
        API.schedule?(mon, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        log(String(format: "monitor on, 13K sender=%llx", ctpSender))
    }

    private func startEventTap() {
        var mask: CGEventMask = 0
        for t: CGEventType in [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .mouseMoved, .tabletPointer, .tabletProximity,
        ] {
            mask |= (1 << t.rawValue)
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                Unmanaged<TouchSources>.fromOpaque(refcon!).takeUnretainedValue().filterCGEvent(type, event)
            },
            userInfo: ctx
        ) else {
            log("CGEvent tap failed (need Accessibility)")
            return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("CGEvent tap on (swallow only while finger down)")
    }

    /// Pass real mouse through. While the 13K finger is down, drop the OS
    /// copy of that click (it lands on the wrong display).
    private func filterCGEvent(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        tapEvents += 1
        if fingerDown {
            switch type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                 .rightMouseDown, .rightMouseUp, .rightMouseDragged, .mouseMoved:
                return nil
            default:
                break
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func readSender(_ client: UnsafeMutableRawPointer) -> UInt64 {
        guard let copy = API.copyServices, let box = copy(client) else { return 0 }
        let arr = box.takeUnretainedValue()
        guard CFArrayGetCount(arr) > 0, let raw = CFArrayGetValueAtIndex(arr, 0) else { return 0 }
        let svc = UnsafeMutableRawPointer(mutating: raw)
        guard let getReg = API.getRegistryID, let p = getReg(svc) else { return 0 }
        return Unmanaged<NSNumber>.fromOpaque(p).takeUnretainedValue().uint64Value
    }

    private func gotHIDEvent(_ event: UnsafeMutableRawPointer) {
        hidEvents += 1
        let type = API.getType?(event) ?? 0
        let sender = API.getSender?(event) ?? 0
        lock.lock()
        senders[sender, default: 0] += 1
        lock.unlock()
        if ctpSender == 0, let matcher { ctpSender = readSender(matcher) }

        let fromCTP = ctpSender != 0 && sender == ctpSender
        let digitizer = (type == 11)
        pushKind(String(format: "hid t=%u s=%llx", type, sender))

        if fromCTP || digitizer {
            ctpEvents += 1
            emitHIDSample(event, type: type, tag: fromCTP ? "ctp" : "dig")
        }
    }

    private func emitHIDSample(_ event: UnsafeMutableRawPointer, type: UInt32, tag: String) {
        var x = API.getFloat?(event, (type << 16)) ?? 0
        var y = API.getFloat?(event, (type << 16) &+ 1) ?? 0
        if x == 0, y == 0 {
            x = Double(API.getInt?(event, type << 16) ?? 0)
            y = Double(API.getInt?(event, (type << 16) &+ 1) ?? 0)
        }
        let touch = (API.getInt?(event, (type << 16) &+ 9) ?? 0) != 0
            || (API.getInt?(event, (type << 16) &+ 8) ?? 0) != 0
        let (nx, ny) = normalize(x, y)
        let down = touch || nx > 0 || ny > 0
        onSample?(TouchSample(
            fingers: down ? [TouchFinger(nx: nx, ny: ny, id: 0)] : [],
            summary: String(format: "%@ t=%u x=%.3f y=%.3f down=%d", tag, type, x, y, down ? 1 : 0)
        ))
    }

    private func usbRecentlyBumped() -> Bool {
        pollUSBReports()
        return ProcessInfo.processInfo.systemUptime - lastUSBBump < 0.30
    }

    private func pollUSBReports() {
        guard let mgr = manager,
              let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return }
        for d in devices {
            guard let debug = IOHIDDeviceGetProperty(d, "DebugState" as CFString) as? NSDictionary,
                  let n = (debug["InputReportCount"] as? NSNumber)?.intValue else { continue }
            if n > usbReports {
                lastUSBBump = ProcessInfo.processInfo.systemUptime
            }
            usbReports = n
            return
        }
    }

    private func tick() {
        if ctpSender == 0, let matcher { ctpSender = readSender(matcher) }
        let kinds = lastKinds.suffix(4).joined(separator: "\n")
        pollUSBReports()
        probeSummary = """
        poll  tip=\(pollTip) cnt=\(pollCount) x=\(pollX) y=\(pollY) ok=\(pollOK)
        finger \(fingerDown ? "DOWN" : "up")
        USB \(usbReports)  HID-noise \(hidEvents)  tap \(tapEvents)
        Last:
        \(kinds)
        """
        onLog?(String(format: "usb=%d tap=%d remap=%d", usbReports, tapEvents, remapped))
        TouchEngine.shared.refreshTrust()
    }

    private func pushKind(_ s: String) {
        lastKinds.append(s)
        if lastKinds.count > 8 { lastKinds.removeFirst(lastKinds.count - 8) }
    }

    private func log(_ s: String) {
        NSLog("13K Touch %@", s)
        onLog?(s)
    }

    private func normalize(_ x: Double, _ y: Double) -> (CGFloat, CGFloat) {
        if x >= 0, x <= 1.05, y >= 0, y <= 1.05 {
            return (CGFloat(x), CGFloat(y))
        }
        if x <= 4096, y <= 4096 {
            return (CGFloat(x / 4096), CGFloat(y / 4096))
        }
        return (CGFloat(min(1, max(0, x))), CGFloat(min(1, max(0, y))))
    }
}

private enum API {
    typealias CreateType = @convention(c) (CFAllocator?, UInt32, CFDictionary?) -> UnsafeMutableRawPointer?
    typealias SetMatching = @convention(c) (UnsafeMutableRawPointer, CFDictionary?) -> Void
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Schedule = @convention(c) (UnsafeMutableRawPointer, CFRunLoop?, CFString) -> Void
    typealias GetType = @convention(c) (UnsafeMutableRawPointer) -> UInt32
    typealias GetFloat = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double
    typealias GetInt = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int64
    typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    typealias GetRegistryID = @convention(c) (UnsafeMutableRawPointer) -> UnsafeRawPointer?
    typealias GetSender = @convention(c) (UnsafeMutableRawPointer) -> UInt64

    static let createWithType: CreateType? = load("IOHIDEventSystemClientCreateWithType")
    static let setMatching: SetMatching? = load("IOHIDEventSystemClientSetMatching")
    static let register: Register? = load("IOHIDEventSystemClientRegisterEventCallback")
    static let schedule: Schedule? = load("IOHIDEventSystemClientScheduleWithRunLoop")
    static let getType: GetType? = load("IOHIDEventGetType")
    static let getFloat: GetFloat? = load("IOHIDEventGetFloatValue")
    static let getInt: GetInt? = load("IOHIDEventGetIntegerValue")
    static let copyServices: CopyServices? = load("IOHIDEventSystemClientCopyServices")
    static let getRegistryID: GetRegistryID? = load("IOHIDServiceClientGetRegistryID")
    static let getSender: GetSender? = load("IOHIDEventGetSenderID")

    private static func load<T>(_ name: String) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
}
