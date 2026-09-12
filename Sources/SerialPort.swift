import Foundation
import Darwin
import IOKit
import IOKit.serial

final class SerialPort {
    private var fd: Int32 = -1
    let path: String

    init(path: String) { self.path = path }
    deinit { closePort() }

    var isOpen: Bool { fd != -1 }

    @discardableResult
    func openPort() -> Bool {
        closePort()
        fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd != -1 else { return false }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            closePort()
            return false
        }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CS8 | CREAD | CLOCAL)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cc.16 = 0 // VMIN
        options.c_cc.17 = 5 // VTIME 0.5s
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            closePort()
            return false
        }

        var status: Int32 = 0
        if ioctl(fd, TIOCMGET, &status) != -1 {
            status &= ~TIOCM_DTR
            status &= ~TIOCM_RTS
            _ = ioctl(fd, TIOCMSET, &status)
        }
        tcflush(fd, TCIOFLUSH)
        usleep(200_000)
        return true
    }

    func closePort() {
        if fd != -1 {
            close(fd)
            fd = -1
        }
    }

    @discardableResult
    func writeString(_ string: String) -> Bool {
        guard fd != -1 else { return false }
        let bytes = Array(string.utf8)
        let n = bytes.withUnsafeBufferPointer { buf -> Int in
            write(fd, buf.baseAddress, buf.count)
        }
        return n == bytes.count
    }

    func readAvailable() -> String {
        guard fd != -1 else { return "" }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { return "" }
        return String(bytes: buffer[0..<Int(n)], encoding: .ascii) ?? ""
    }

    static func findCH340Callout() -> String? {
        if let matched = findCH340ViaIOKit() { return matched }
        // Fallback: first cu.usbserial / cu.wchusbserial
        let dev = "/dev"
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dev) else { return nil }
        for name in items.sorted() {
            if name.hasPrefix("cu.usbserial") || name.hasPrefix("cu.wchusbserial") {
                return "\(dev)/\(name)"
            }
        }
        return nil
    }

    private static func findCH340ViaIOKit() -> String? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOSerialBSDClient")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let callout = stringProperty(service, "IOCalloutDevice") else { continue }
            if usbIdentityMatchesCH340(service) {
                return callout
            }
        }
        return nil
    }

    private static func usbIdentityMatchesCH340(_ service: io_object_t) -> Bool {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<12 {
            let vendor = intProperty(current, "idVendor")
            let product = intProperty(current, "idProduct")
            if vendor == 0x1A86 && product == 0x7523 {
                return true
            }
            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr != KERN_SUCCESS { return false }
            current = parent
        }
        return false
    }

    private static func stringProperty(_ service: io_object_t, _ key: String) -> String? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (ref.takeRetainedValue() as? String)
    }

    private static func intProperty(_ service: io_object_t, _ key: String) -> Int? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = ref.takeRetainedValue()
        if let n = value as? NSNumber { return n.intValue }
        if let n = value as? Int { return n }
        return nil
    }
}
