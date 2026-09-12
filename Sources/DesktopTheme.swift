import AppKit
import Foundation

enum DesktopTheme: String, CaseIterable, Identifiable {
    case `default`, black, white
    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return L10n.t("Default", "預設")
        case .black: return L10n.t("Black", "黑底")
        case .white: return L10n.t("White", "白底")
        }
    }

    static var current: DesktopTheme {
        DesktopTheme(rawValue: UserDefaults.standard.string(forKey: "desktopTheme") ?? "default") ?? .default
    }

    static func apply(_ theme: DesktopTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: "desktopTheme")
        guard theme != .default else { return }
        guard let url = Bundle.main.url(forResource: theme.rawValue, withExtension: "png") else { return }
        let screens = NSScreen.screens.filter { $0.localizedName.localizedCaseInsensitiveContains("13K") }
        let targets = screens.isEmpty ? NSScreen.screens : screens
        for screen in targets {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
            ])
        }
    }
}

enum TextEnhancement {
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "textEnhancement") }
        set {
            UserDefaults.standard.set(newValue, forKey: "textEnhancement")
            apply()
        }
    }

    static func apply() {
        // Official "Text Enhancement": disable font smoothing so type is sharper on e-ink.
        if isOn {
            CFPreferencesSetAppValue("AppleFontSmoothing" as CFString, 0 as CFNumber, kCFPreferencesAnyApplication)
        } else {
            CFPreferencesSetAppValue("AppleFontSmoothing" as CFString, nil, kCFPreferencesAnyApplication)
        }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    }
}

enum EinkPrep {
    static func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openNightShift() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
