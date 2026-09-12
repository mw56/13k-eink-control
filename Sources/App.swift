import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Stillcolor.apply()
        TextEnhancement.apply()
        _ = ShortcutCenter.shared
        ControlSocket.shared.start()
        if UserDefaults.standard.object(forKey: "loginItem") == nil {
            LoginItem.setEnabled(true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ControlSocket.shared.stop()
        DeviceController.shared.shutdown()
    }
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
    }
}
