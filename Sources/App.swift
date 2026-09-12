import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Stillcolor.apply()
        TextEnhancement.apply()
        _ = ShortcutCenter.shared
        ControlSocket.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DeviceController.shared.beginStop()
        ControlSocket.shared.stop()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        DeviceController.shared.beginStop()
        ControlSocket.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show()
        return true
    }
}

extension Notification.Name {
    static let openControlPanel = Notification.Name("openControlPanel")
}

@main
struct PaperlikeControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var device = DeviceController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: device.isConnected ? "display" : "display.trianglebadge.exclamationmark")
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(L10n.t("Quit 13K Control", "結束 13K Control")) {
                    AppTermination.quit()
                }
                .keyboardShortcut("q")
            }
        }
    }
}
