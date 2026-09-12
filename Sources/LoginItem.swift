import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: "loginItem")
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "loginItem")
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                fallbackLoginItem(on)
            }
        } else {
            fallbackLoginItem(on)
        }
    }

    private static func fallbackLoginItem(_ on: Bool) {
        let path = Bundle.main.bundlePath
        let script: String
        if on {
            script = """
            tell application "System Events"
              if (path of every login item) does not contain "\(path)" then
                make login item at end with properties {path:"\(path)", hidden:true}
              end if
            end tell
            """
        } else {
            script = """
            tell application "System Events"
              repeat with li in (get login items)
                try
                  if path of li is "\(path)" then delete li
                end try
              end repeat
            end tell
            """
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
