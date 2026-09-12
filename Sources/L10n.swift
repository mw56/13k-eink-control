import Foundation

enum L10n {
    static var isZh: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func t(_ en: String, _ zh: String) -> String { isZh ? zh : en }
}
