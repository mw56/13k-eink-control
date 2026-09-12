import AppKit
import Darwin
import Foundation

enum AppTermination {
    private static var quitting = false

    static func quit() {
        guard !quitting else { return }
        quitting = true
        DeviceController.shared.beginStop()
        ControlSocket.shared.stop()
        NSApp.windows.forEach { $0.close() }
        NSApp.terminate(nil)
        // SwiftUI MenuBarExtra + LSUIElement often swallows terminate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Darwin.exit(0)
        }
    }

    static func relaunch() {
        guard !quitting else { return }
        let quoted = shellQuote(Bundle.main.bundlePath)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", "sleep 0.8; /usr/bin/open \(quoted)"]
        try? proc.run()
        quit()
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
