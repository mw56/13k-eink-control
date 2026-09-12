import Foundation
import Darwin

/// Local JSON control socket (`$TMPDIR/paperlike.sock`).
final class ControlSocket {
    static let shared = ControlSocket()
    private var listenFD: Int32 = -1
    private var thread: Thread?
    private var running = false

    static var path: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("paperlike.sock")
    }

    func start() {
        stop()
        running = true
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "paperlike.sock"
        t.start()
        thread = t
    }

    func stop() {
        running = false
        if listenFD != -1 {
            Darwin.shutdown(listenFD, SHUT_RDWR)
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(atPath: Self.path)
    }

    private func runLoop() {
        signal(SIGPIPE, SIG_IGN)
        try? FileManager.default.removeItem(atPath: Self.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        listenFD = fd
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(Self.path.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            raw.initializeMemory(as: UInt8.self, repeating: 0, count: 104)
            pathBytes.withUnsafeBufferPointer { src in
                raw.copyMemory(from: src.baseAddress!, byteCount: min(src.count, 103))
            }
        }
        let ok = withUnsafePointer(to: &addr) { ptr -> Bool in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard ok, listen(fd, 4) == 0 else {
            close(fd)
            listenFD = -1
            return
        }
        chmod(Self.path, 0o666)

        while running {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            handleClient(client)
            close(client)
        }
    }

    private func handleClient(_ client: Int32) {
        let flags = fcntl(client, F_GETFL)
        if flags >= 0 { _ = fcntl(client, F_SETFL, flags & ~O_NONBLOCK) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        for _ in 0..<64 {
            let n = read(client, &buf, buf.count)
            if n < 0 {
                if errno == EINTR { continue }
                break
            }
            if n == 0 { break }
            data.append(contentsOf: buf[0..<Int(n)])
            if data.contains(0x0A) { break }
        }
        // Probe connections (CLI daemon_is_running) connect and close with no payload.
        guard !data.isEmpty else { return }
        var response = process(data)
        if response.last != 0x0A { response.append(0x0A) }
        _ = response.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            var sent = 0
            while sent < response.count {
                let w = write(client, base + sent, response.count - sent)
                if w <= 0 { break }
                sent += w
            }
            return sent
        }
    }

    private func process(_ data: Data) -> Data {
        func json(_ obj: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(#"{"ok":false}"#.utf8)
        }
        guard let line = data.split(separator: 0x0A, maxSplits: 1, omittingEmptySubsequences: true).first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let type = obj["type"] as? String else {
            return json(["ok": false, "error": "bad request"])
        }
        if type == "query" {
            let info = DeviceController.shared.queryAll()
            return json(["ok": true, "results": [["info": info]]])
        }
        if type == "commands", let commands = obj["commands"] as? [[String: Any]] {
            var results: [[String: Any]] = []
            for c in commands {
                let cmd = UInt8(truncatingIfNeeded: (c["cmd"] as? Int) ?? Int(c["cmd"] as? Double ?? 0))
                let opt = UInt8(truncatingIfNeeded: (c["opt"] as? Int) ?? Int(c["opt"] as? Double ?? 0))
                let pkts = DeviceController.shared.sendRaw(cmd: cmd, opt: opt)
                results.append([
                    "cmd": Int(cmd),
                    "opt": Int(opt),
                    "label": c["label"] as? String ?? "",
                    "response": pkts.map { ["cmd": Int($0.cmd), "opt": Int($0.opt), "payload": $0.payload] },
                ])
            }
            return json(["ok": true, "results": results])
        }
        return json(["ok": false, "error": "unknown type"])
    }
}
