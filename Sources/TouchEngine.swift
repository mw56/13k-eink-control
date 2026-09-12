import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import IOKit.hid

/// Rebuilt 13K touch path. The previous seize + SimpleClient approach never
/// saw digitizer packets (DriverKit keeps the USB pipe; SimpleClient is silent).
/// This engine:
/// 1. Does **not** seize the digitizer (so WindowServer still sees it)
/// 2. Listens with a HID **Monitor** client (the only client type that delivered events here)
/// 3. Listens for tablet/mouse CGEvents
/// 4. Shows a live probe panel on the main display so a touch either increments
///    a counter or we know the OS swallowed it
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
    @Published var twoFingerScroll: Bool
    @Published var longPressRightClick: Bool
    @Published var nativeBind: Bool
    @Published var screenChoice: String
    @Published var lastHID = "—"
    @Published var lastMapped = "—"
    @Published var statusLine = ""
    @Published var hidReports = 0
    @Published var probeText = ""

    var injecting: Bool { enabled && digitizerPresent }
    var mappedScreenName: String { screenName }

    private let sources = TouchSources()
    private let overlay = TouchCursor()
    private let probe = TouchProbePanel()
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

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "touchEnabled") as? Bool ?? true
        overlayEnabled = d.object(forKey: "touchOverlay") as? Bool ?? true
        invertX = d.bool(forKey: "touchInvertX")
        invertY = d.bool(forKey: "touchInvertY")
        swapXY = d.bool(forKey: "touchSwapXY")
        twoFingerScroll = d.object(forKey: "touchTwoFingerScroll") as? Bool ?? true
        longPressRightClick = d.object(forKey: "touchLongPressRight") as? Bool ?? true
        nativeBind = d.object(forKey: "touchNativeBind") as? Bool ?? true
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
            DispatchQueue.main.async { self?.note(line) }
        }
        sources.onSample = { [weak self] sample in
            self?.handle(sample)
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
        probe.hide()
        if mouseDown { post(.leftMouseUp, at: lastPoint) }
        mouseDown = false
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "touchEnabled")
        if !on { probe.hide(); overlay.hide() }
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
    func setTwoFingerScroll(_ on: Bool) { twoFingerScroll = on; UserDefaults.standard.set(on, forKey: "touchTwoFingerScroll") }
    func setLongPressRight(_ on: Bool) { longPressRightClick = on; UserDefaults.standard.set(on, forKey: "touchLongPressRight") }
    func setNativeBind(_ on: Bool) { nativeBind = on; UserDefaults.standard.set(on, forKey: "touchNativeBind") }
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
        DispatchQueue.main.async {
            self.hidReports += 1
            self.lastHID = sample.summary
            self.refreshTrust()
        }
        guard enabled, !bounds.isEmpty else { return }
        var nx = sample.nx
        var ny = sample.ny
        if swapXY { swap(&nx, &ny) }
        if invertX { nx = 1 - nx }
        if invertY { ny = 1 - ny }
        nx = min(1, max(0, nx))
        ny = min(1, max(0, ny))
        let pt = CGPoint(x: bounds.minX + nx * bounds.width, y: bounds.minY + ny * bounds.height)
        lastPoint = pt
        DispatchQueue.main.async {
            self.lastMapped = String(format: "%.0f, %.0f", pt.x, pt.y)
            if self.overlayEnabled { self.overlay.show(quartz: pt, cocoaFrame: self.frame, quartzBounds: self.bounds) }
        }

        if sample.alreadyDelivered {
            return
        }
        liftWork?.cancel()
        if sample.down {
            if !mouseDown {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastClickAt < NSEvent.doubleClickInterval, hypot(pt.x - lastClickPoint.x, pt.y - lastClickPoint.y) < 12 {
                    clickCount += 1
                } else { clickCount = 1 }
                lastClickAt = now
                lastClickPoint = pt
                mouseDown = true
                post(.leftMouseDown, at: pt)
            } else {
                post(.leftMouseDragged, at: pt)
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mouseDown else { return }
            self.post(.leftMouseUp, at: self.lastPoint)
            self.mouseDown = false
            DispatchQueue.main.async { self.overlay.hide() }
        }
        liftWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func post(_ type: CGEventType, at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        let button: CGMouseButton = (type == .rightMouseDown || type == .rightMouseUp) ? .right : .left
        guard let ev = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        ev.setIntegerValueField(.mouseEventClickState, value: clickCount)
        ev.post(tap: .cghidEventTap)
        ev.post(tap: .cgSessionEventTap)
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

    private func note(_ line: String) {
        lastHID = line
        probeText = sources.probeSummary
        probe.update(sources.probeSummary)
        try? line.write(toFile: "/tmp/13k-touch.log", atomically: true, encoding: .utf8)
    }

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
        if Thread.isMainThread { statusLine = line; probe.update(sources.probeSummary) }
        else { DispatchQueue.main.async { self.statusLine = line } }
    }
}

typealias TouchBridge = TouchEngine

struct TouchSample {
    var nx: CGFloat
    var ny: CGFloat
    var down: Bool
    var summary: String
    var alreadyDelivered = false
}

// MARK: - Cursor on the 13K

private final class TouchCursor {
    private var window: NSWindow?

    func show(quartz: CGPoint, cocoaFrame: CGRect, quartzBounds: CGRect) {
        let nx = quartzBounds.width == 0 ? 0 : (quartz.x - quartzBounds.minX) / quartzBounds.width
        let ny = quartzBounds.height == 0 ? 0 : (quartz.y - quartzBounds.minY) / quartzBounds.height
        let cocoa = CGPoint(x: cocoaFrame.minX + nx * cocoaFrame.width, y: cocoaFrame.maxY - ny * cocoaFrame.height)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 36, height: 36), styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
            v.wantsLayer = true
            v.layer?.cornerRadius = 18
            v.layer?.borderWidth = 2
            v.layer?.borderColor = NSColor.systemOrange.cgColor
            v.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
            w.contentView = v
            window = w
        }
        window?.setFrameOrigin(NSPoint(x: cocoa.x - 18, y: cocoa.y - 18))
        window?.orderFrontRegardless()
    }

    func hide() { window?.orderOut(nil) }
}

/// Always-on-top probe on the **main** display so you can watch counts while touching the 13K.
private final class TouchProbePanel {
    private var panel: NSPanel?
    private var label: NSTextField?

    func show() {
        DispatchQueue.main.async {
            if self.panel == nil {
                let p = NSPanel(
                    contentRect: NSRect(x: 40, y: 80, width: 420, height: 220),
                    styleMask: [.titled, .closable, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                p.title = "13K Touch probe"
                p.isFloatingPanel = true
                p.level = .floating
                p.hidesOnDeactivate = false
                p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let tf = NSTextField(frame: NSRect(x: 12, y: 12, width: 396, height: 176))
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                tf.stringValue = "waiting…"
                p.contentView?.addSubview(tf)
                self.label = tf
                self.panel = p
            }
            self.panel?.orderFrontRegardless()
        }
    }

    func update(_ text: String) {
        DispatchQueue.main.async { self.label?.stringValue = text }
    }

    func hide() {
        DispatchQueue.main.async { self.panel?.orderOut(nil) }
    }
}
