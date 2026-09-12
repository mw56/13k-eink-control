import AppKit
import Carbon
import Foundation

final class CarbonHotkeys {
    static let shared = CarbonHotkeys()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x504C3133 // 'PL13'

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<CarbonHotkeys>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            if status == noErr, hotKeyID.signature == mgr.signature {
                mgr.handlers[hotKeyID.id]?()
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, ptr, &eventHandler)
    }

    func register(id: UInt32, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        unregister(id: id)
        handlers[id] = handler
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), carbon, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { refs[id] = ref }
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
    }
}

struct HotkeyBinding: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += Self.keyName(keyCode)
        return s
    }

    static func keyName(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[code] ?? String(format: "Key%d", code)
    }
}

final class ShortcutCenter: ObservableObject {
    static let shared = ShortcutCenter()
    @Published var refresh: HotkeyBinding?
    @Published var modeCycle: HotkeyBinding?
    @Published var contrastUp: HotkeyBinding?
    @Published var contrastDown: HotkeyBinding?

    private init() {
        refresh = load("hkRefresh") ?? HotkeyBinding(keyCode: 15, modifiers: [.control, .option]) // ⌃⌥R
        modeCycle = load("hkMode")
        contrastUp = load("hkContrastUp")
        contrastDown = load("hkContrastDown")
        applyAll()
    }

    func saveRefresh(_ b: HotkeyBinding?) { refresh = b; store("hkRefresh", b); applyAll() }
    func saveMode(_ b: HotkeyBinding?) { modeCycle = b; store("hkMode", b); applyAll() }
    func saveContrastUp(_ b: HotkeyBinding?) { contrastUp = b; store("hkContrastUp", b); applyAll() }
    func saveContrastDown(_ b: HotkeyBinding?) { contrastDown = b; store("hkContrastDown", b); applyAll() }

    private func applyAll() {
        bind(id: 1, refresh) { DeviceController.shared.refresh() }
        bind(id: 2, modeCycle) {
            let cur = DeviceController.shared.mode
            let all = DisplayMode.allCases
            let idx = all.firstIndex(of: cur) ?? 0
            let next = all[(idx + 1) % all.count]
            DeviceController.shared.setMode(next)
        }
        bind(id: 3, contrastUp) {
            DeviceController.shared.setContrast(DeviceController.shared.contrast + 1)
        }
        bind(id: 4, contrastDown) {
            DeviceController.shared.setContrast(DeviceController.shared.contrast - 1)
        }
    }

    private func bind(id: UInt32, _ binding: HotkeyBinding?, handler: @escaping () -> Void) {
        CarbonHotkeys.shared.unregister(id: id)
        guard let binding else { return }
        CarbonHotkeys.shared.register(id: id, keyCode: binding.keyCode, modifiers: binding.modifiers, handler: handler)
    }

    private func store(_ key: String, _ b: HotkeyBinding?) {
        if let b {
            UserDefaults.standard.set(Int(b.keyCode), forKey: key + ".code")
            UserDefaults.standard.set(b.modifiers.rawValue, forKey: key + ".mods")
        } else {
            UserDefaults.standard.removeObject(forKey: key + ".code")
            UserDefaults.standard.removeObject(forKey: key + ".mods")
        }
    }

    private func load(_ key: String) -> HotkeyBinding? {
        guard UserDefaults.standard.object(forKey: key + ".code") != nil else { return nil }
        let code = UInt16(UserDefaults.standard.integer(forKey: key + ".code"))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: key + ".mods")))
        return HotkeyBinding(keyCode: code, modifiers: mods)
    }
}
