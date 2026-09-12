import SwiftUI

struct MenuBarView: View {
    @ObservedObject var device = DeviceController.shared
    @ObservedObject var shortcuts = ShortcutCenter.shared
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modeRow
            contrastBlock
            frontLightBlock
            brightnessBlock
            temperatureBlock
            autoClearBlock
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(width: 460, height: 520)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(device.isConnected ? Color.green : Color.red)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("13K Control")
                    .font(.headline)
                Text(L10n.t("Unofficial · not DASUNG", "非官方 · 與大上無關"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(device.isConnected
                     ? (device.portPath as NSString).lastPathComponent
                     : (device.lastError.isEmpty ? L10n.t("Disconnected", "未連線") : device.lastError))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if device.mcuVersion != 0 {
                Text(String(format: "MCU 0x%02X", device.mcuVersion))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("Display Mode", "顯示模式"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(DisplayMode.allCases) { mode in
                    Button(mode.title) { device.setMode(mode) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(device.mode == mode ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(device.mode == mode ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help(mode.subtitle)
                }
            }
        }
    }

    private var contrastBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("Contrast / Speed", "對比 / 速度"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(device.contrast)  \(ContrastLevel.label(device.contrast))")
                    .font(.caption.monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { Double(device.contrast) },
                    set: { device.setContrast(Int($0.rounded())) }
                ),
                in: Double(ContrastLevel.min)...Double(ContrastLevel.max),
                step: 1
            )
            HStack {
                Text("Fast++++").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("Clear", "清晰")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var frontLightBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("Front Light", "前光"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { device.frontLight },
                set: { device.setFrontLight($0) }
            )) {
                ForEach(FrontLightMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var brightnessBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("Light Brightness", "前光亮度"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(device.brightness)")
                    .font(.caption.monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { Double(device.brightness) },
                    set: { device.setBrightness(Int($0.rounded())) }
                ),
                in: 0...64,
                step: 1
            )
            HStack {
                Text(L10n.t("Dark", "暗")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("Bright", "亮")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var temperatureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("Color Temperature", "色溫"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(device.temperature)")
                    .font(.caption.monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { Double(device.temperature) },
                    set: { device.setTemperature(Int($0.rounded())) }
                ),
                in: 0...100,
                step: 1
            )
            HStack {
                Text(L10n.t("Warm", "暖")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("Cold", "冷")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var autoClearBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { device.autoClearEnabled },
                set: { device.setAutoClear(enabled: $0) }
            )) {
                Text(L10n.t("Auto Clear Ghost", "自動清殘影"))
            }
            .toggleStyle(.checkbox)
            if device.autoClearEnabled {
                HStack {
                    Text(L10n.t("Interval (sec ≥ 30)", "間隔（秒，≥30）"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("\(device.autoClearSeconds)", value: Binding(
                        get: { device.autoClearSeconds },
                        set: { device.setAutoClear(enabled: true, seconds: $0) }
                    ), in: 30...600, step: 10)
                    .frame(width: 120)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.t("Ghost Cleanup", "立即清屏")) {
                device.refresh()
            }
            .keyboardShortcut("r", modifiers: [.control, .option])
            Button(L10n.t("Reconnect", "重新連線")) {
                device.reconnectNow()
            }
            Spacer()
            Button(L10n.t("Settings…", "設定…")) { showSettings = true }
            Button(L10n.t("Quit", "結束")) {
                device.shutdown()
                NSApp.terminate(nil)
            }
        }
    }
}
