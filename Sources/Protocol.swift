import Foundation

/// DASUNG Paperlike 13K serial protocol (same on Windows V2.0 and Mac V2.0.3).
/// 24 uppercase ASCII hex chars: 5FF5 + cmd + opt + 12-digit payload + A0FA
enum PaperlikeCmd: UInt8 {
    case contrast = 0x01
    case mode = 0x02
    case refresh = 0x03
    case frontLight = 0x07
    case temperature = 0x08
    case brightness = 0x09
    case query = 0x0A
    case activate = 0x20
}

enum PaperlikeOpt {
    static let queryMCU: UInt8 = 0x10
    static let queryDisplay: UInt8 = 0x13
    static let activateOn: UInt8 = 0x01
    static let activateOff: UInt8 = 0x00
}

struct PaperlikePacket {
    let cmd: UInt8
    let opt: UInt8
    let payload: String

    var value: UInt8 {
        guard payload.count >= 4,
              let v = UInt8(payload.dropFirst(2).prefix(2), radix: 16) else { return 0 }
        return v
    }
}

enum PaperlikeProto {
    static func makePacket(cmd: UInt8, opt: UInt8) -> String {
        String(format: "5FF5%02X%02X000000000000A0FA", cmd, opt)
    }

    static func parse(_ data: String) -> [PaperlikePacket] {
        let text = data.uppercased()
        var results: [PaperlikePacket] = []
        var search = text.startIndex
        while let range = text.range(of: "5FF5", range: search..<text.endIndex) {
            let start = range.lowerBound
            guard let end = text.index(start, offsetBy: 24, limitedBy: text.endIndex) else { break }
            let pkt = String(text[start..<end])
            if pkt.hasSuffix("A0FA"),
               let cmd = UInt8(pkt.dropFirst(4).prefix(2), radix: 16),
               let opt = UInt8(pkt.dropFirst(6).prefix(2), radix: 16) {
                let payload = String(pkt.dropFirst(8).prefix(12))
                results.append(PaperlikePacket(cmd: cmd, opt: opt, payload: payload))
                search = end
            } else {
                search = text.index(after: range.lowerBound)
            }
        }
        return results
    }
}

enum DisplayMode: Int, CaseIterable, Identifiable {
    case web = 1, text = 2, image = 3, active = 4, heavy = 5
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .web: return L10n.t("Web", "網頁")
        case .text: return L10n.t("Text", "文字")
        case .image: return L10n.t("Image", "圖像")
        case .active: return L10n.t("Active", "動態")
        case .heavy: return L10n.t("Heavy", "高畫質")
        }
    }

    var subtitle: String {
        switch self {
        case .web: return L10n.t("M1 · no flicker", "M1 · 少殘影")
        case .text: return L10n.t("M2 · sharp type", "M2 · 文字銳利")
        case .image: return L10n.t("M3 · photos", "M3 · 照片")
        case .active: return L10n.t("M4 · motion", "M4 · 動態")
        case .heavy: return L10n.t("M5 · max quality", "M5 · 最高畫質")
        }
    }

    /// Hardware quirk (also in official / paperlike-rs): querying mode 1 can return 5.
    static func fromDevice(_ raw: Int) -> DisplayMode? {
        if raw == 5 { return .web }
        return DisplayMode(rawValue: raw)
    }
}

enum FrontLightMode: Int, CaseIterable, Identifiable {
    case off = 0, warm = 1, cold = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: return L10n.t("Off", "關")
        case .warm: return L10n.t("Warm", "暖光")
        case .cold: return L10n.t("Cold", "冷光")
        }
    }
}

enum ContrastLevel {
    static let min = 1
    static let max = 9

    static func label(_ value: Int) -> String {
        switch value {
        case 1: return "Fast++++"
        case 2: return "Fast+++"
        case 3: return "Fast++"
        case 4: return "Fast+"
        case 5: return "Fast"
        case 6: return L10n.t("Clear", "清晰")
        case 7: return L10n.t("Clear+", "清晰+")
        case 8: return L10n.t("Clear++", "清晰++")
        default: return L10n.t("Clear+++", "清晰+++")
        }
    }
}
