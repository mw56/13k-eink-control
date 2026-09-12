import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var device = DeviceController.shared
    @ObservedObject var shortcuts = ShortcutCenter.shared
    @ObservedObject var touch = TouchBridge.shared
    @State private var gpuDitherOff = Stillcolor.isEnabled
    @State private var textEnhancement = TextEnhancement.isOn
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var theme = DesktopTheme.current
    @State private var recording: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab.tabItem { Text(L10n.t("General", "一般")) }
                touchTab.tabItem { Text(L10n.t("Touch", "觸控")) }
                shortcutTab.tabItem { Text(L10n.t("Shortcuts", "快捷鍵")) }
                macTab.tabItem { Text(L10n.t("macOS", "macOS")) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            Divider()
            HStack {
                Spacer()
                Button(L10n.t("Close", "關閉")) {
                    SettingsWindow.close()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 460, minHeight: 500)
        .background(KeyCatcher(recording: $recording, onCapture: capture))
    }

    private var generalTab: some View {
        Form {
            Section {
                Text(L10n.t("Unofficial · not DASUNG. Controller for the 13K panel only.", "非官方 · 與大上無關。僅作為 13K 的控制器。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.t("Startup", "啟動")) {
                Toggle(L10n.t("Open at login", "開機自動啟動"), isOn: Binding(
                    get: { loginEnabled },
                    set: {
                        loginEnabled = $0
                        LoginItem.setEnabled($0)
                    }
                ))
            }
            Section(L10n.t("Theme settings", "主題")) {
                Picker(L10n.t("13K desktop", "13K 桌布"), selection: Binding(
                    get: { theme },
                    set: {
                        theme = $0
                        DesktopTheme.apply($0)
                    }
                )) {
                    ForEach(DesktopTheme.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
            }
            Section(L10n.t("Text Enhancement", "文字增強")) {
                Toggle(L10n.t("Sharper UI fonts (disable smoothing)", "關閉字體平滑，文字更銳利"), isOn: Binding(
                    get: { textEnhancement },
                    set: {
                        textEnhancement = $0
                        TextEnhancement.isOn = $0
                    }
                ))
            }
            Section(L10n.t("GPU dithering", "GPU 抖動")) {
                Toggle(L10n.t("Disable GPU dithering (Stillcolor)", "關閉 GPU 抖動（Stillcolor）"), isOn: Binding(
                    get: { gpuDitherOff },
                    set: {
                        gpuDitherOff = $0
                        Stillcolor.isEnabled = $0
                        Stillcolor.apply()
                    }
                ))
                Text(L10n.t(
                    "Same framebuffer switch the official Mac client uses. Helps color banding on e-ink.",
                    "與官方 Mac 客戶端相同的 framebuffer 開關，可減少電子紙色帶。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(L10n.t("Connection", "連線")) {
                LabeledContent("USB") {
                    Text(device.portPath.isEmpty ? "—" : device.portPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button(L10n.t("Reconnect now", "立即重連")) { device.reconnectNow() }
            }
            Section {
                Button(L10n.t("Restart 13K Control", "重新啟動 13K Control")) {
                    AppTermination.relaunch()
                }
                Button(L10n.t("Quit 13K Control", "結束 13K Control"), role: .destructive) {
                    AppTermination.quit()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var touchTab: some View {
        Form {
            Section {
                Text(L10n.t(
                    "Rebuilt listener: HID Monitor (does not steal the USB pipe) + tablet/mouse tap. A probe window on the main screen shows live counters — those numbers must jump when you touch the 13K.",
                    "觸控已重寫：用 HID Monitor（不搶 USB）加上系統手寫板／滑鼠監聽。主螢幕會跳出探針視窗，摸 13K 時數字必須往上跳。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(L10n.t("Mapping", "對應")) {
                Toggle(L10n.t("Enable 13K touch", "啟用 13K 觸控"), isOn: Binding(
                    get: { touch.enabled },
                    set: { touch.setEnabled($0) }
                ))
                LabeledContent(L10n.t("Digitizer", "觸控裝置")) {
                    Text(touch.digitizerPresent
                         ? L10n.t("USB2IIC · present", "USB2IIC · 在線")
                         : L10n.t("Not found", "未找到"))
                        .foregroundStyle(touch.digitizerPresent ? Color.primary : Color.secondary)
                }
                LabeledContent(L10n.t("Status", "狀態")) {
                    Text(touch.statusLine)
                }
                LabeledContent(L10n.t("Events", "事件")) {
                    Text("\(touch.hidReports)  \(touch.lastHID)")
                        .font(.caption.monospaced())
                        .lineLimit(2)
                }
            }
            Section(L10n.t("Accessibility", "輔助使用")) {
                LabeledContent(L10n.t("Permission", "權限")) {
                    Text(touch.accessibilityTrusted
                         ? L10n.t("Granted", "已允許")
                         : L10n.t("Required for clicks", "點擊需要此權限"))
                        .foregroundStyle(touch.accessibilityTrusted ? Color.green : Color.orange)
                }
                Button(L10n.t("Open Accessibility settings…", "打開輔助使用設定…")) {
                    touch.openAccessibilitySettings()
                }
                Button(L10n.t("Relaunch to apply permission", "重新啟動以套用權限")) {
                    AppTermination.relaunch()
                }
                Text(L10n.t(
                    "Use the 13K Control that lives in /Applications. After flipping the switch, press Restart — macOS only applies Accessibility to a new process. Ad-hoc builds can show as on while the API still says no; relaunch after toggling off/on.",
                    "請允許「應用程式」裡那一份 13K Control。打開開關後一定要按「重新啟動」，輔助使用只對新進程生效。ad-hoc 簽名有時開關是開的、程式仍讀成未授權，請關掉再開一次再重啟。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(L10n.t("Native bind", "系統綁定")) {
                Toggle(L10n.t("Tell macOS this digitizer belongs to the 13K", "告訴 macOS：這塊觸控板屬於 13K"), isOn: Binding(
                    get: { touch.nativeBind },
                    set: { touch.setNativeBind($0) }
                ))
                Text(L10n.t(
                    "Best-effort: write the 13K DisplayID onto AppleUserHIDEventDriver (the association Windows exposes and the vendor Mac client never sets). Mouse emulation above is the reliable path.",
                    "盡力而為：把 13K 的 DisplayID 寫進系統 HID 驅動（Windows 有這個對應，官方 Mac 客戶端沒做）。真正穩的是上面的滑鼠模擬。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(L10n.t("Target display", "目標螢幕")) {
                Picker(L10n.t("Map onto", "對應到"), selection: Binding(
                    get: { touch.screenChoice },
                    set: { touch.setScreenChoice($0) }
                )) {
                    Text(L10n.t("Auto (13K)", "自動（13K）")).tag("auto")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
            Section(L10n.t("Calibration", "校正")) {
                Toggle(L10n.t("Invert X", "水平翻轉"), isOn: Binding(
                    get: { touch.invertX },
                    set: { touch.setInvertX($0) }
                ))
                Toggle(L10n.t("Invert Y", "垂直翻轉"), isOn: Binding(
                    get: { touch.invertY },
                    set: { touch.setInvertY($0) }
                ))
                Toggle(L10n.t("Swap X/Y", "交換 X/Y"), isOn: Binding(
                    get: { touch.swapXY },
                    set: { touch.setSwapXY($0) }
                ))
                Toggle(L10n.t("Show touch pointer", "顯示觸控游標"), isOn: Binding(
                    get: { touch.overlayEnabled },
                    set: { touch.setOverlay($0) }
                ))
                LabeledContent("HID") { Text(touch.lastHID).font(.caption.monospaced()) }
                LabeledContent(L10n.t("Mapped", "對應座標")) {
                    Text(touch.lastMapped).font(.caption.monospaced())
                }
            }
            Section(L10n.t("Gestures", "手勢")) {
                Toggle(L10n.t("Two-finger scroll", "雙指捲動"), isOn: Binding(
                    get: { touch.twoFingerScroll },
                    set: { touch.setTwoFingerScroll($0) }
                ))
                Toggle(L10n.t("Long-press for right-click", "長按當右鍵"), isOn: Binding(
                    get: { touch.longPressRightClick },
                    set: { touch.setLongPressRight($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutTab: some View {
        Form {
            Text(L10n.t(
                "Global shortcuts do not need Accessibility permission.",
                "全域快捷鍵不需要「輔助使用」權限。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            hotkeyRow(L10n.t("Ghost Cleanup", "立即清屏"), binding: shortcuts.refresh, id: "refresh")
            hotkeyRow(L10n.t("Cycle display mode", "循環顯示模式"), binding: shortcuts.modeCycle, id: "mode")
            hotkeyRow(L10n.t("Increase contrast", "提高對比"), binding: shortcuts.contrastUp, id: "up")
            hotkeyRow(L10n.t("Decrease contrast", "降低對比"), binding: shortcuts.contrastDown, id: "down")
        }
        .formStyle(.grouped)
    }

    private var macTab: some View {
        Form {
            Section(L10n.t("Windows client checklist, on Mac", "Windows 客戶端的 Mac 對應設定")) {
                Text(L10n.t(
                    "Dasung tells Windows users to use a high-contrast theme and turn Night Light off. These buttons open the Mac equivalents. None of this requires their closed client.",
                    "大上在 Windows 上要求高對比主題、關掉夜燈。這些按鈕會打開 Mac 上對應的系統設定，不需要官方客戶端。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(L10n.t("Accessibility → Display (Reduce transparency / Increase contrast / Reduce motion)", "輔助使用 → 顯示（降低透明度 / 增加對比 / 減少動態效果）")) {
                    EinkPrep.openDisplaySettings()
                }
                Button(L10n.t("Displays (Night Shift / True Tone / resolution)", "顯示器（Night Shift / True Tone / 解析度）")) {
                    EinkPrep.openNightShift()
                }
                Text(L10n.t(
                    "Set the 13K to 3200×2400 @ 37Hz when the dock allows it. It is currently easy to fall back to 2048×1536 through HDMI hubs.",
                    "若擴充座允許，請把 13K 設成 3200×2400 @ 37Hz。經 HDMI/擴充座時很容易落到 2048×1536。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func hotkeyRow(_ title: String, binding: HotkeyBinding?, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording == id ? L10n.t("Type shortcut…", "請按快捷鍵…") : (binding?.display ?? L10n.t("Click to record", "點擊錄製"))) {
                recording = id
            }
            .buttonStyle(.bordered)
            if binding != nil {
                Button(role: .destructive) {
                    assign(id, nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func capture(_ event: NSEvent) {
        guard let recording else { return }
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard !mods.isEmpty else { return }
        assign(recording, HotkeyBinding(keyCode: event.keyCode, modifiers: mods))
        self.recording = nil
    }

    private func assign(_ id: String, _ binding: HotkeyBinding?) {
        switch id {
        case "refresh": shortcuts.saveRefresh(binding)
        case "mode": shortcuts.saveMode(binding)
        case "up": shortcuts.saveContrastUp(binding)
        case "down": shortcuts.saveContrastDown(binding)
        default: break
        }
    }
}

struct KeyCatcher: NSViewRepresentable {
    @Binding var recording: String?
    var onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> CatchView {
        let v = CatchView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: CatchView, context: Context) {
        nsView.onCapture = onCapture
        nsView.active = recording != nil
        if recording != nil {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    final class CatchView: NSView {
        var onCapture: ((NSEvent) -> Void)?
        var active = false
        override var acceptsFirstResponder: Bool { true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard active else { return super.performKeyEquivalent(with: event) }
            onCapture?(event)
            return true
        }
    }
}
