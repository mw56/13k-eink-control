import Foundation
import Combine

final class DeviceController: ObservableObject {
    static let shared = DeviceController()

    @Published var isConnected = false
    @Published var lastError = ""
    @Published var portPath = ""
    @Published var mcuVersion: UInt8 = 0
    @Published var mode: DisplayMode = .web
    @Published var contrast: Int = 5
    @Published var frontLight: FrontLightMode = .off
    @Published var brightness: Int = 32
    @Published var temperature: Int = 3
    @Published var autoClearEnabled = true
    @Published var autoClearSeconds = 30

    private var port: SerialPort?
    private let queue = DispatchQueue(label: "local.paperlike.serial")
    private var keepAlive: DispatchSourceTimer?
    private var autoClear: DispatchSourceTimer?
    private var reconnect: DispatchSourceTimer?
    private let lock = NSLock()
    private var stopping = false

    private init() {
        autoClearEnabled = UserDefaults.standard.object(forKey: "autoClearEnabled") as? Bool ?? true
        let stored = UserDefaults.standard.integer(forKey: "autoClearSeconds")
        autoClearSeconds = stored >= 30 ? stored : 30
        queue.async { [weak self] in self?.connectAndInit() }
        startKeepAlive()
        startReconnectWatch()
        refreshAutoClearTimer()
    }

    func setMode(_ value: DisplayMode) {
        mode = value
        send(cmd: PaperlikeCmd.mode.rawValue, opt: UInt8(value.rawValue))
    }

    func setContrast(_ value: Int) {
        let v = min(ContrastLevel.max, max(ContrastLevel.min, value))
        contrast = v
        send(cmd: PaperlikeCmd.contrast.rawValue, opt: UInt8(v))
    }

    func setFrontLight(_ value: FrontLightMode) {
        frontLight = value
        send(cmd: PaperlikeCmd.frontLight.rawValue, opt: UInt8(value.rawValue))
    }

    func setBrightness(_ value: Int) {
        let v = min(64, max(0, value))
        brightness = v
        send(cmd: PaperlikeCmd.brightness.rawValue, opt: UInt8(v))
    }

    func setTemperature(_ value: Int) {
        let v = min(100, max(0, value))
        temperature = v
        send(cmd: PaperlikeCmd.temperature.rawValue, opt: UInt8(v))
    }

    func refresh() {
        send(cmd: PaperlikeCmd.refresh.rawValue, opt: 0x01)
    }

    func setAutoClear(enabled: Bool, seconds: Int? = nil) {
        autoClearEnabled = enabled
        if let seconds { autoClearSeconds = max(30, seconds) }
        UserDefaults.standard.set(autoClearEnabled, forKey: "autoClearEnabled")
        UserDefaults.standard.set(autoClearSeconds, forKey: "autoClearSeconds")
        refreshAutoClearTimer()
    }

    func sendRaw(cmd: UInt8, opt: UInt8) -> [PaperlikePacket] {
        var packets: [PaperlikePacket] = []
        queue.sync {
            packets = sendLocked(cmd: cmd, opt: opt, waitMs: 250)
        }
        return packets
    }

    func queryAll() -> [String: Int] {
        var info: [String: Int] = [:]
        queue.sync {
            info = queryLocked()
            applyInfo(info)
        }
        return info
    }

    func reconnectNow() {
        guard !stopping else { return }
        queue.async { [weak self] in self?.connectAndInit() }
    }

    /// Non-blocking stop so Quit is not stuck on serial I/O.
    func beginStop() {
        stopping = true
        keepAlive?.cancel()
        autoClear?.cancel()
        reconnect?.cancel()
        keepAlive = nil
        autoClear = nil
        reconnect = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.port?.closePort()
            self.port = nil
        }
    }

    func shutdown() {
        beginStop()
    }

    private func connectAndInit() {
        guard !stopping else { return }
        lock.lock()
        defer { lock.unlock() }
        if stopping { return }
        port?.closePort()
        port = nil
        guard let path = SerialPort.findCH340Callout() else {
            publish(connected: false, error: L10n.t("13K USB serial not found", "找不到 13K 的 USB 串口"), path: "")
            return
        }
        let serial = SerialPort(path: path)
        guard serial.openPort() else {
            publish(connected: false, error: L10n.t("Failed to open \(path)", "無法打開 \(path)"), path: path)
            return
        }
        _ = serial.readAvailable()
        port = serial
        publish(connected: true, error: "", path: path)
        _ = sendLocked(cmd: PaperlikeCmd.activate.rawValue, opt: PaperlikeOpt.activateOn, waitMs: 300)
        let info = queryLocked()
        applyInfo(info)
    }

    private func send(cmd: UInt8, opt: UInt8) {
        queue.async { [weak self] in
            _ = self?.sendLocked(cmd: cmd, opt: opt, waitMs: 120)
        }
    }

    @discardableResult
    private func sendLocked(cmd: UInt8, opt: UInt8, waitMs: UInt32) -> [PaperlikePacket] {
        guard let port, port.isOpen else { return [] }
        _ = port.readAvailable()
        let packet = PaperlikeProto.makePacket(cmd: cmd, opt: opt)
        let wrote = port.writeString(packet)
        if !wrote {
            port.closePort()
            self.port = nil
            publish(connected: false, error: L10n.t("Serial write failed", "串口寫入失敗"), path: "")
            return []
        }
        usleep(waitMs * 1000)
        let raw = port.readAvailable()
        return PaperlikeProto.parse(raw)
    }

    private func queryLocked() -> [String: Int] {
        var info: [String: Int] = [:]
        let queries: [(UInt8, String)] = [
            (PaperlikeOpt.queryMCU, "mcu"),
            (PaperlikeOpt.queryDisplay, "display"),
            (PaperlikeCmd.contrast.rawValue, "contrast"),
            (PaperlikeCmd.mode.rawValue, "mode"),
            (PaperlikeCmd.frontLight.rawValue, "front"),
            (PaperlikeCmd.brightness.rawValue, "brightness"),
            (PaperlikeCmd.temperature.rawValue, "temperature"),
        ]
        for (opt, key) in queries {
            let pkts = sendLocked(cmd: PaperlikeCmd.query.rawValue, opt: opt, waitMs: opt == PaperlikeOpt.queryMCU ? 400 : 200)
            if let pkt = pkts.first(where: { $0.cmd == 0xF0 }) {
                info[key] = Int(pkt.value)
            }
        }
        return info
    }

    private func applyInfo(_ info: [String: Int]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let v = info["mcu"] { self.mcuVersion = UInt8(v) }
            if let v = info["mode"], let parsed = DisplayMode.fromDevice(v) { self.mode = parsed }
            if let v = info["contrast"] { self.contrast = min(9, max(1, v)) }
            if let v = info["front"], let fl = FrontLightMode(rawValue: v) { self.frontLight = fl }
            if let v = info["brightness"] { self.brightness = min(64, max(0, v)) }
            if let v = info["temperature"] { self.temperature = min(100, max(0, v)) }
        }
    }

    private func publish(connected: Bool, error: String, path: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = connected
            self?.lastError = error
            self?.portPath = path
        }
    }

    private func startKeepAlive() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopping else { return }
            if let port = self.port, port.isOpen {
                _ = self.sendLocked(cmd: PaperlikeCmd.activate.rawValue, opt: PaperlikeOpt.activateOn, waitMs: 80)
            }
        }
        timer.resume()
        keepAlive = timer
    }

    private func startReconnectWatch() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopping else { return }
            let path = SerialPort.findCH340Callout()
            let open = self.port?.isOpen == true
            if path == nil && open {
                self.port?.closePort()
                self.port = nil
                self.publish(connected: false, error: L10n.t("Display unplugged", "顯示器已拔除"), path: "")
            } else if path != nil && !open {
                self.connectAndInit()
            }
        }
        timer.resume()
        reconnect = timer
    }

    private func refreshAutoClearTimer() {
        autoClear?.cancel()
        autoClear = nil
        guard autoClearEnabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let secs = max(30, autoClearSeconds)
        timer.schedule(deadline: .now() + .seconds(secs), repeating: .seconds(secs))
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopping else { return }
            _ = self.sendLocked(cmd: PaperlikeCmd.refresh.rawValue, opt: 0x01, waitMs: 80)
        }
        timer.resume()
        autoClear = timer
    }
}
