import Foundation

enum TouchGestureKind: String, CaseIterable, Identifiable {
    case oneFingerTap
    case oneFingerSwipe
    case oneFingerLongPress
    case oneFingerLongPressDrag
    case twoFingerTap
    case twoFingerSwipe
    case pinch
    case fiveFingerPinch
    case fourFingerSwipeUp
    case fourFingerSwipeDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneFingerTap: return L10n.t("Tap", "單指輕點")
        case .oneFingerSwipe: return L10n.t("One-finger swipe", "單指滑動")
        case .oneFingerLongPress: return L10n.t("Long-press (lift)", "單指長按鬆開")
        case .oneFingerLongPressDrag: return L10n.t("Long-press then move", "單指長按後移動")
        case .twoFingerTap: return L10n.t("Two-finger tap", "雙指輕點")
        case .twoFingerSwipe: return L10n.t("Two-finger swipe", "雙指滑動")
        case .pinch: return L10n.t("Pinch", "雙指捏合／張開")
        case .fiveFingerPinch: return L10n.t("Five-finger pinch-in", "五指收合併攏")
        case .fourFingerSwipeUp: return L10n.t("Four-finger swipe up", "四指向上")
        case .fourFingerSwipeDown: return L10n.t("Four-finger swipe down", "四指向下")
        }
    }
}

enum TouchAction: String, CaseIterable, Identifiable {
    case none
    case leftClick
    case rightClick
    case scroll
    case drag
    case zoom
    case missionControl
    case appExpose
    case launchpad
    case showDesktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.t("None", "無")
        case .leftClick: return L10n.t("Click", "點擊")
        case .rightClick: return L10n.t("Right-click", "右鍵")
        case .scroll: return L10n.t("Scroll", "捲動")
        case .drag: return L10n.t("Drag", "拖曳")
        case .zoom: return L10n.t("Zoom", "縮放")
        case .missionControl: return L10n.t("Mission Control", "指揮中心")
        case .appExpose: return L10n.t("App Exposé", "App Exposé")
        case .launchpad: return L10n.t("Launchpad", "開啟應用程式選單")
        case .showDesktop: return L10n.t("Show Desktop", "顯示桌面")
        }
    }

    var isContinuous: Bool {
        switch self {
        case .scroll, .drag, .zoom: return true
        default: return false
        }
    }
}

enum GesturePhase {
    case began, changed, ended
}

struct GesturePayload {
    var point: CGPoint
    var delta: CGPoint
    var scaleDelta: CGFloat
}

final class TouchBindings: ObservableObject {
    static let shared = TouchBindings()

    /// iPad-like defaults after reversing scroll 180°.
    static let iPadDefaults: [TouchGestureKind: TouchAction] = [
        .oneFingerTap: .leftClick,
        .oneFingerSwipe: .scroll,
        .oneFingerLongPress: .rightClick,
        .oneFingerLongPressDrag: .drag,
        .twoFingerTap: .rightClick,
        .twoFingerSwipe: .scroll,
        .pinch: .zoom,
        .fiveFingerPinch: .none,
        .fourFingerSwipeUp: .none,
        .fourFingerSwipeDown: .none,
    ]

    @Published private(set) var map: [TouchGestureKind: TouchAction]

    private init() {
        var loaded: [TouchGestureKind: TouchAction] = Self.iPadDefaults
        for kind in TouchGestureKind.allCases {
            if let raw = UserDefaults.standard.string(forKey: Self.key(kind)),
               let action = TouchAction(rawValue: raw) {
                loaded[kind] = action
            }
        }
        map = loaded
    }

    func action(for kind: TouchGestureKind) -> TouchAction {
        map[kind] ?? .none
    }

    func set(_ kind: TouchGestureKind, _ action: TouchAction) {
        map[kind] = action
        UserDefaults.standard.set(action.rawValue, forKey: Self.key(kind))
        objectWillChange.send()
    }

    func resetToiPadDefaults() {
        for kind in TouchGestureKind.allCases {
            let action = Self.iPadDefaults[kind] ?? .none
            map[kind] = action
            UserDefaults.standard.set(action.rawValue, forKey: Self.key(kind))
        }
        objectWillChange.send()
    }

    private static func key(_ kind: TouchGestureKind) -> String {
        "touchBind.\(kind.rawValue)"
    }
}
