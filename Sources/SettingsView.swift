import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var device = DeviceController.shared
    @ObservedObject var shortcuts = ShortcutCenter.shared
    @State private var gpuDitherOff = Stillcolor.isEnabled
    @State private var textEnhancement = TextEnhancement.isOn
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var theme = DesktopTheme.current
    @State private var recording: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab.tabItem { Text(L10n.t("General", "一般")) }
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
