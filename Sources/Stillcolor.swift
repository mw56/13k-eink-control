import Foundation
import IOKit

/// macOS GPU dithering off via public IOMobileFramebuffer properties.
enum Stillcolor {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "gpuDitheringOff") }
        set { UserDefaults.standard.set(newValue, forKey: "gpuDitheringOff") }
    }

    static func apply() {
        let off = isEnabled
        set(["enableDither": off ? kCFBooleanFalse! : kCFBooleanTrue!], externalOnly: false)
        set(["uniformity2D": kCFBooleanFalse!], externalOnly: false)
    }

    private static func set(_ props: [String: CFTypeRef], externalOnly: Bool) {
        var iterator = io_iterator_t()
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferAP"), &iterator)
        guard kr == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            if externalOnly {
                let ext = IORegistryEntryCreateCFProperty(service, "external" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
                let isExternal = (ext as? Bool) ?? false
                if !isExternal { continue }
            }
            for (key, value) in props {
                _ = IORegistryEntrySetCFProperty(service, key as CFString, value)
            }
        }
    }
}
