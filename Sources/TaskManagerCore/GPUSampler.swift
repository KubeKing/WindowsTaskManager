import Foundation
import CoreFoundation
import IOKit

/// Driver-reported counters read locally, without polling subprocesses or privileged helpers.
/// IOKit is public; these registry keys are driver-specific and may be absent on other Macs.
public final class GPUSampler {
    public init() {}

    public func sample() -> [GPUMetrics] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [GPUMetrics] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }
            let name = property(service, "model") as? String ?? "GPU"
            let statistics = property(service, "PerformanceStatistics") as? [String: Any] ?? [:]
            var gpu = Self.decode(id: String(registryID), name: name, statistics: statistics)
            if let configuration = property(service, "GPUConfigurationVariable") as? [String: Any],
               let cores = Self.bytes(configuration["num_cores"]), cores > 0, cores <= UInt64(Int.max) {
                gpu.coreCount = Int(cores)
            }
            result.append(gpu)
        }
        return result.sorted { $0.id < $1.id }
    }

    private func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func decode(id: String, name: String, statistics: [String: Any]) -> GPUMetrics {
        var result = GPUMetrics(id: id, name: name)
        result.utilization = percent(statistics["Device Utilization %"])
        result.rendererUtilization = percent(statistics["Renderer Utilization %"])
        result.tilerUtilization = percent(statistics["Tiler Utilization %"])
        result.memoryInUseBytes = bytes(statistics["In use system memory"])
        result.memoryAllocatedBytes = bytes(statistics["Alloc system memory"])
        return result
    }

    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }
    private static func percent(_ value: Any?) -> Double? {
        guard let value = number(value)?.doubleValue, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
    private static func bytes(_ value: Any?) -> UInt64? {
        guard let number = number(value) else { return nil }
        // Preserve integer precision, including unsigned values larger than Int64.max.
        let type = String(cString: number.objCType)
        if ["Q", "L", "I", "S", "C"].contains(type) { return number.uint64Value }
        if ["q", "l", "i", "s", "c"].contains(type) {
            return number.int64Value >= 0 ? number.uint64Value : nil
        }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value.rounded(.towardZero) == value,
              value < 18_446_744_073_709_551_616.0 else { return nil }
        return UInt64(value)
    }
}
