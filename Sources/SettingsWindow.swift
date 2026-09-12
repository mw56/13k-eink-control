import AppKit
import SwiftUI

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = L10n.t("13K Control Settings", "13K Control 設定")
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 480, height: 560))
        win.isReleasedWhenClosed = false
        win.level = .normal
        win.center()
        win.delegate = CloseDelegate.shared
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    static func close() {
        window?.performClose(nil)
    }

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        static let shared = CloseDelegate()
        func windowWillClose(_ notification: Notification) {
            SettingsWindow.window = nil
        }
    }
}
