import AppKit
import CoreFoundation
import CoreGraphics
import Darwin

/// Triggers the same Mission Control family as the Mac trackpad.
enum MacDesktopActions {
    static func missionControl() {
        if sendDock("com.apple.expose.awake") { return }
        openApp("/System/Applications/Mission Control.app")
        hotkey(keyCode: 126, flags: .maskControl) // Control+Up
    }

    static func appExpose() {
        if sendDock("com.apple.expose.front.awake") { return }
        hotkey(keyCode: 125, flags: .maskControl) // Control+Down
    }

    static func launchpad() {
        if sendDock("com.apple.launchpad.toggle") { return }
        if openApp("/System/Applications/Launchpad.app") { return }
        if openApp("/System/Library/CoreServices/Launchpad.app") { return }
        hotkey(keyCode: 118, flags: []) // F4 on many Macs
    }

    static func showDesktop() {
        if sendDock("com.apple.showdesktop.awake") { return }
        hotkey(keyCode: 103, flags: []) // F11
    }

    @discardableResult
    private static func sendDock(_ name: String) -> Bool {
        guard let send = dockSend else { return false }
        send(name as CFString, 0)
        return true
    }

    private static let dockSend: (@convention(c) (CFString, Int32) -> Void)? = {
        let handle = dlopen("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", RTLD_LAZY)
        guard handle != nil, let sym = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CFString, Int32) -> Void).self)
    }()

    @discardableResult
    private static func openApp(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    private static func hotkey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}
