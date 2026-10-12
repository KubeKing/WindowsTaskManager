import Foundation
import Darwin
import IOKit

/// Static hardware facts read once from public sysctl and IOKit metadata.
/// Missing frequencies, cache sizes, or topology remain unavailable rather than estimated.
public struct HardwareInfo: Sendable {
    public var physicalCPUs: Int
    public var logicalCPUs: Int
    public var sockets: Int?
    public var model: String
    public var cpuName: String
    public var l1DataBytes: UInt64?
    public var l1InstructionBytes: UInt64?
    public var l2Bytes: UInt64?
    public var l3Bytes: UInt64?
    public var baseFrequencyHz: UInt64?
    public var gpuName: String
    public var virtualizationSupported: Bool?

    private static let detected = detect()
    public static func read() -> HardwareInfo { detected }

    private static func detect() -> HardwareInfo {
        let logical = positiveInteger("hw.logicalcpu").map(Int.init) ?? ProcessInfo.processInfo.processorCount
        let physical = positiveInteger("hw.physicalcpu").map(Int.init) ?? logical
        return HardwareInfo(
            physicalCPUs: physical,
            logicalCPUs: logical,
            sockets: positiveInteger("hw.packages").map(Int.init),
            model: string("hw.model") ?? "Mac",
            cpuName: string("machdep.cpu.brand_string") ?? "Apple silicon",
            l1DataBytes: positiveInteger("hw.l1dcachesize"),
            l1InstructionBytes: positiveInteger("hw.l1icachesize"),
            l2Bytes: positiveInteger("hw.l2cachesize"),
            l3Bytes: positiveInteger("hw.l3cachesize"),
            baseFrequencyHz: positiveInteger("hw.cpufrequency"),
            gpuName: gpuModel() ?? "Apple integrated GPU",
            virtualizationSupported: integer("kern.hv_support").map { $0 != 0 }
        )
    }

    private static func positiveInteger(_ key: String) -> UInt64? {
        guard let value = integer(key), value > 0 else { return nil }
        return value
    }

    private static func integer(_ key: String) -> UInt64? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<UInt32>.size {
            var value: UInt32 = 0
            guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
            return UInt64(value)
        }
        if size == MemoryLayout<UInt64>.size {
            var value: UInt64 = 0
            guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
            return value
        }
        return nil
    }

    private static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func gpuModel() -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { continue }
            if let name = property as? String, !name.isEmpty { return name }
            if let data = property as? Data, let name = String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8), !name.isEmpty { return name }
        }
        return nil
    }
}
