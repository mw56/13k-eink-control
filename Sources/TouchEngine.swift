import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import IOKit.hid

/// 13K touch path:
/// 1. Does **not** seize the digitizer (WindowServer keeps the USB pipe)
/// 2. Polls HID tip/X/Y elements for multi-touch (primary sample source)
/// 3. CGEvent tap swallows the OS copy of clicks that land on the wrong display
final class TouchEngine: ObservableObject {
    static let shared = TouchEngine()

    @Published var enabled: Bool
    @Published var digitizerPresent = false
    @Published var seized = false
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    @Published var postEventAccess = false
    @Published var overlayEnabled: Bool
    @Published var invertX: Bool
    @Published var invertY: Bool
    @Published var swapXY: Bool
    @Published var screenChoice: String
    @Published var lastHID = "—"
    @Published var lastMapped = "—"
    @Published var statusLine = ""
    @Published var hidReports = 0
    @Published var bindings = TouchBindings.shared

    var injecting: Bool { enabled && digitizerPresent }
    var mappedScreenName: String { screenName }

    private let sources = TouchSources()
    private let overlay = TouchCursor()
    private var eventSource: CGEventSource?
    private var mouseDown = false
    private var lastPoint = CGPoint.zero
    private var bounds = CGRect.zero
    private var frame = CGRect.zero
    private var screenName = ""
    private var displayID: CGDirectDisplayID = 0
    private var clickCount: Int64 = 1
    private var lastClickAt: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var liftWork: DispatchWorkItem?
    private var dragActive = false
    private var lastUIPublish: TimeInterval = 0
    private var pendingReports = 0
    private lazy var gestures: TouchGestures = {
        let g = TouchGestures()
        g.onOverlay = { [weak self] pts in
            guard let self, self.overlayEnabled else { return }
            DispatchQueue.main.async {
                self.overlay.show(points: pts, cocoaFrame: self.frame, quartzBounds: self.bounds)
            }
        }
        g.onHide = { [weak self] in
            DispatchQueue.main.async { self?.overlay.hide() }
        }
        g.onGesture = { [weak self] kind, phase, payload in
            self?.apply(kind, phase, payload)
        }
        return g
    }()

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "touchEnabled") as? Bool ?? true
        // Overlay dots flash on e-ink; off by default after first install.
        overlayEnabled = d.object(forKey: "touchOverlay") as? Bool ?? false
        invertX = d.bool(forKey: "touchInvertX")
        invertY = d.bool(forKey: "touchInvertY")
        swapXY = d.bool(forKey: "touchSwapXY")
        screenChoice = d.string(forKey: "touchScreen") ?? "auto"
        eventSource = CGEventSource(stateID: .hidSystemState)
        recacheScreen()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.recacheScreen() }
        refreshStatus()
    }

    func start() {
        sources.onLog = { [weak self] line in
            #if DEBUG
            DispatchQueue.main.async { self?.note(line) }
            #else
            _ = self
            _ = line
            #endif
        }
        sources.onSample = { [weak self] sample in
            // Gestures + long-press timers share the main queue.
            DispatchQueue.main.async { self?.handle(sample) }
        }
        sources.remapPoint = { loc in
            TouchEngine.shared.remapTo13K(loc)
        }
        sources.onPresence = { [weak self] present in
            DispatchQueue.main.async {
                self?.digitizerPresent = present
                self?.refreshStatus()
            }
        }
        sources.start()
        refreshTrust()
        recacheScreen()
        refreshStatus()
    }

    func stop() {
        sources.stop()
        overlay.hide()
        gestures.reset()
        dragActive = false
        mouseDown = false
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "touchEnabled")
        if !on { overlay.hide() }
        refreshStatus()
    }

    func setOverlay(_ on: Bool) {
        overlayEnabled = on
        UserDefaults.standard.set(on, forKey: "touchOverlay")
        if !on { overlay.hide() }
    }

    func setInvertX(_ on: Bool) { invertX = on; UserDefaults.standard.set(on, forKey: "touchInvertX") }
    func setInvertY(_ on: Bool) { invertY = on; UserDefaults.standard.set(on, forKey: "touchInvertY") }
    func setSwapXY(_ on: Bool) { swapXY = on; UserDefaults.standard.set(on, forKey: "touchSwapXY") }
    func setScreenChoice(_ name: String) {
        screenChoice = name
        UserDefaults.standard.set(name, forKey: "touchScreen")
        recacheScreen()
    }

    func availableScreens() -> [String] { ["auto"] + NSScreen.screens.map(\.localizedName) }

    func refreshTrust() {
        let ax = AXIsProcessTrusted()
        let post = CGPreflightPostEventAccess()
        DispatchQueue.main.async {
            self.accessibilityTrusted = ax || post
            self.postEventAccess = post
            self.refreshStatus()
        }
    }

    func promptAccess() {
        if AXIsProcessTrusted() || CGPreflightPostEventAccess() { return }
        _ = CGRequestPostEventAccess()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Map a quartz point from whatever display the OS put it on onto the 13K.
    func remapTo13K(_ loc: CGPoint) -> CGPoint {
        recacheScreenIfStale()
        guard !bounds.isEmpty else { return loc }
        if bounds.contains(loc) { return loc }
        let src = sourceDisplay(containing: loc)
        guard src.width > 0, src.height > 0 else { return loc }
        let nx = min(1, max(0, (loc.x - src.minX) / src.width))
        let ny = min(1, max(0, (loc.y - src.minY) / src.height))
        return CGPoint(x: bounds.minX + nx * bounds.width, y: bounds.minY + ny * bounds.height)
    }

    var einkBounds: CGRect { bounds }
    var einkFrame: CGRect { frame }

    private func recacheScreenIfStale() {
        if bounds.isEmpty { recacheScreen() }
    }

    private func sourceDisplay(containing loc: CGPoint) -> CGRect {
        for s in NSScreen.screens {
            let did = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let r = CGDisplayBounds(CGDirectDisplayID(did))
            if r.contains(loc) { return r }
        }
        if let main = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            let did = (main.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayBounds(CGDirectDisplayID(did))
        }
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    func openAccessibilitySettings() {
        promptAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - samples → 13K

    private func handle(_ sample: TouchSample) {
        pendingReports += 1
        guard enabled, !bounds.isEmpty else {
            flushDiagnostics(sample.summary, mapped: nil, force: sample.fingers.isEmpty)
            return
        }
        let points = sample.fingers.map { finger -> CGPoint in
            var nx = finger.nx
            var ny = finger.ny
            if swapXY { swap(&nx, &ny) }
            if invertX { nx = 1 - nx }
            if invertY { ny = 1 - ny }
            nx = min(1, max(0, nx))
            ny = min(1, max(0, ny))
            return CGPoint(x: bounds.minX + nx * bounds.width, y: bounds.minY + ny * bounds.height)
        }
        if let p = points.first {
            lastPoint = p
        }
        let mapped = points.first.map { String(format: "%.0f, %.0f ×%d", $0.x, $0.y, points.count) }
        flushDiagnostics(sample.summary, mapped: mapped, force: sample.fingers.isEmpty)
        gestures.ingest(fingers: points, now: ProcessInfo.processInfo.systemUptime)
    }

    /// Throttle @Published diagnostics so MenuBarExtra is not redrawing at poll rate.
    private func flushDiagnostics(_ summary: String, mapped: String?, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastUIPublish >= 0.12 else { return }
        lastUIPublish = now
        hidReports += pendingReports
        pendingReports = 0
        lastHID = summary
        if let mapped { lastMapped = mapped }
    }

    private func apply(_ kind: TouchGestureKind, _ phase: GesturePhase, _ p: GesturePayload) {
        let action = bindings.action(for: kind)
        guard action != .none else { return }
        switch action {
        case .none:
            return
        case .leftClick:
            guard phase == .ended else { return }
            click(at: p.point, right: false)
        case .rightClick:
            guard phase == .ended else { return }
            click(at: p.point, right: true)
        case .scroll:
            if phase == .changed {
                postScroll(dx: p.delta.x, dy: p.delta.y)
            }
        case .drag:
            switch phase {
            case .began:
                dragActive = true
                post(.leftMouseDown, at: p.point, clickCount: 1)
            case .changed:
                if dragActive { post(.leftMouseDragged, at: p.point, clickCount: 1) }
            case .ended:
                if dragActive {
                    post(.leftMouseUp, at: p.point, clickCount: 1)
                    dragActive = false
                }
            }
        case .zoom:
            if phase == .began || phase == .changed {
                postZoom(p.scaleDelta)
            }
        case .missionControl:
            guard phase == .ended else { return }
            MacDesktopActions.missionControl()
        case .appExpose:
            guard phase == .ended else { return }
            MacDesktopActions.appExpose()
        case .launchpad:
            guard phase == .ended else { return }
            MacDesktopActions.launchpad()
        case .showDesktop:
            guard phase == .ended else { return }
            MacDesktopActions.showDesktop()
        }
    }

    private func click(at point: CGPoint, right: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if !right, now - lastClickAt < NSEvent.doubleClickInterval, hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 18 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickAt = now
        lastClickPoint = point
        if right {
            post(.rightMouseDown, at: point, clickCount: 1)
            post(.rightMouseUp, at: point, clickCount: 1)
        } else {
            post(.leftMouseDown, at: point, clickCount: clickCount)
            post(.leftMouseUp, at: point, clickCount: clickCount)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint, clickCount: Int64) {
        CGWarpMouseCursorPosition(point)
        let button: CGMouseButton = (type == .rightMouseDown || type == .rightMouseUp) ? .right : .left
        guard let ev = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        ev.setIntegerValueField(.mouseEventClickState, value: clickCount)
        // HID tap alone is enough; dual-post duplicated clicks in some apps.
        ev.post(tap: .cghidEventTap)
    }

    private func postScroll(dx: CGFloat, dy: CGFloat) {
        // 180° from v1.3.0 so the page moves with the finger like iPad.
        let wheelY = Int32((dy * 1.4).rounded())
        let wheelX = Int32((dx * 1.4).rounded())
        guard wheelX != 0 || wheelY != 0 else { return }
        guard let ev = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheelY,
            wheel2: wheelX,
            wheel3: 0
        ) else { return }
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        ev.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
        ev.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
        ev.post(tap: .cghidEventTap)
    }

    private func postZoom(_ delta: CGFloat) {
        guard abs(delta) > 0.2 else { return }
        // Command+scroll is the usual macOS pinch-zoom in Safari, Maps, Preview.
        guard let ev = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(delta.rounded()),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        ev.flags = .maskCommand
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        ev.post(tap: .cghidEventTap)
    }

    private func recacheScreen() {
        let screens = NSScreen.screens
        let picked: NSScreen? = {
            if screenChoice != "auto", let s = screens.first(where: { $0.localizedName == screenChoice }) { return s }
            if let s = screens.first(where: {
                $0.localizedName.localizedCaseInsensitiveContains("13K")
                    || $0.localizedName.localizedCaseInsensitiveContains("Paperlike")
            }) { return s }
            let others = screens.filter { $0 != NSScreen.main }
            if others.count == 1 { return others[0] }
            return others.first { abs(($0.frame.width / max($0.frame.height, 1)) - 4.0 / 3.0) < 0.2 } ?? others.first
        }()
        if let s = picked {
            let did = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            displayID = CGDirectDisplayID(did)
            bounds = CGDisplayBounds(displayID)
            frame = s.frame
            screenName = s.localizedName
        } else {
            displayID = 0
            bounds = .zero
            frame = .zero
            screenName = ""
        }
        refreshStatus()
    }

    #if DEBUG
    private func note(_ line: String) {
        lastHID = line
        try? line.write(toFile: "/tmp/13k-touch.log", atomically: true, encoding: .utf8)
    }
    #endif

    private func refreshStatus() {
        let line: String
        if !enabled {
            line = L10n.t("Touch off", "觸控已關")
        } else if !digitizerPresent {
            line = L10n.t("Touch: no digitizer", "觸控：找不到觸控板")
        } else if !accessibilityTrusted {
            line = L10n.t("Tracking 13K — grant Accessibility for clicks", "已追蹤 13K · 點擊請開輔助使用")
        } else if screenName.isEmpty {
            line = L10n.t("Touch: 13K screen not found", "觸控：找不到 13K 畫面")
        } else {
            line = L10n.t("Touch → \(screenName)", "觸控 → \(screenName)")
        }
        if Thread.isMainThread { statusLine = line }
        else { DispatchQueue.main.async { self.statusLine = line } }
    }
}

typealias TouchBridge = TouchEngine

struct TouchFinger {
    var nx: CGFloat
    var ny: CGFloat
    var id: Int
}

struct TouchSample {
    var fingers: [TouchFinger]
    var summary: String
}

// MARK: - Cursor on the 13K

private final class TouchCursor {
    private var windows: [NSWindow] = []

    func show(points: [CGPoint], cocoaFrame: CGRect, quartzBounds: CGRect) {
        while windows.count < points.count { windows.append(makeDot()) }
        while windows.count > points.count {
            windows.removeLast().orderOut(nil)
        }
        for (i, quartz) in points.enumerated() {
            let nx = quartzBounds.width == 0 ? 0 : (quartz.x - quartzBounds.minX) / quartzBounds.width
            let ny = quartzBounds.height == 0 ? 0 : (quartz.y - quartzBounds.minY) / quartzBounds.height
            let cocoa = CGPoint(x: cocoaFrame.minX + nx * cocoaFrame.width, y: cocoaFrame.maxY - ny * cocoaFrame.height)
            windows[i].setFrameOrigin(NSPoint(x: cocoa.x - 16, y: cocoa.y - 16))
            windows[i].orderFrontRegardless()
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
    }

    private func makeDot() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 32, height: 32), styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        v.wantsLayer = true
        v.layer?.cornerRadius = 16
        v.layer?.borderWidth = 2
        v.layer?.borderColor = NSColor.systemOrange.cgColor
        v.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.22).cgColor
        w.contentView = v
        return w
    }
}

