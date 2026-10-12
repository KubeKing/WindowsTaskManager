import Foundation
import Darwin
import IOKit

public struct CPUFrequencyMetrics: Sendable {
    public var performanceMHz: Double? = nil
    public var efficiencyMHz: Double? = nil
    public var note = "Experimental local IOReport readings; frequency is averaged over active cluster residency, excluding idle time."
    public init() {}
}

enum FrequencyMath {
    /// Older chips encode Hz; newer chips can encode kHz. Reject ambiguous or
    /// implausible tables instead of accidentally reporting a timer frequency.
    static func decodeTable(_ data: Data) -> [Double]? {
        guard !data.isEmpty, data.count % 8 == 0 else { return nil }
        let raw: [Double] = stride(from: 0, to: data.count, by: 8).map { offset in
            Double(data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) })
        }.filter { $0 > 0 }
        guard let max = raw.max() else { return nil }
        let divisor = max >= 100_000_000 ? 1_000_000.0 : 1_000.0
        let mhz = raw.map { $0 / divisor }
        guard mhz.allSatisfy({ (200...10_000).contains($0) }), zip(mhz, mhz.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
        return mhz
    }
    static func weighted(states: [(name: String, residency: UInt64)], mhz: [Double]) -> (sum: Double, active: Double)? {
        var sum = 0.0, active = 0.0
        var indices: Set<Int> = []
        for state in states {
            if ["IDLE", "OFF", "DOWN"].contains(state.name.uppercased()) { continue }
            let parts = state.name.split(separator: "P")
            guard parts.count == 2, parts[0].first == "V", Int(parts[1]) != nil,
                  let index = Int(parts[0].dropFirst()), mhz.indices.contains(index), indices.insert(index).inserted else { return nil }
            let duration = Double(state.residency)
            sum += duration * mhz[index]; active += duration
        }
        guard indices.count == mhz.count, active > 0, sum.isFinite, active.isFinite else { return nil }
        return (sum, active)
    }
}

/// Private system-library symbols are resolved optionally. Missing symbols,
/// channels or verified state tables leave readings unavailable; never block
/// sampling or require a privileged helper. All owned CF objects are released.
final class CPUFrequencySampler {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    private typealias Samples = @convention(c) (UnsafeMutableRawPointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Delta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Name = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias Count = @convention(c) (CFDictionary) -> Int32
    private typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias Residency = @convention(c) (CFDictionary, Int32) -> UInt64
    private struct API {
        var copy: CopyChannels; var subscribe: Subscribe; var samples: Samples; var delta: Delta
        var name: Name; var subgroup: Name; var format: Count; var count: Count; var stateName: StateName; var residency: Residency
    }
    private var library: UnsafeMutableRawPointer?
    private var api: API?
    private var subscription: UnsafeMutableRawPointer?
    private var channels: CFMutableDictionary?
    private var previous: CFDictionary?
    private var tables: [String: [Double]] = [:]
    private var unavailableReason = "CPU frequency channels are unavailable on this Mac."

    init() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL) else { return }
        self.library = library
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            guard let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let copy = symbol("IOReportCopyChannelsInGroup", CopyChannels.self),
              let subscribe = symbol("IOReportCreateSubscription", Subscribe.self),
              let samples = symbol("IOReportCreateSamples", Samples.self),
              let delta = symbol("IOReportCreateSamplesDelta", Delta.self),
              let name = symbol("IOReportChannelGetChannelName", Name.self),
              let subgroup = symbol("IOReportChannelGetSubGroup", Name.self),
              let format = symbol("IOReportChannelGetFormat", Count.self),
              let count = symbol("IOReportStateGetCount", Count.self),
              let stateName = symbol("IOReportStateGetNameForIndex", StateName.self),
              let residency = symbol("IOReportStateGetResidency", Residency.self) else { return }
        let api = API(copy: copy, subscribe: subscribe, samples: samples, delta: delta, name: name, subgroup: subgroup, format: format, count: count, stateName: stateName, residency: residency)
        guard let desired = copy("CPU Stats" as CFString, "CPU Complex Performance States" as CFString, 0, 0, 0)?.takeRetainedValue() else { return }
        var actual: Unmanaged<CFMutableDictionary>?
        let sub = subscribe(nil, desired, &actual, 0, nil)
        channels = actual?.takeRetainedValue()
        subscription = sub
        guard sub != nil, channels != nil else { return }
        self.api = api
        tables = Self.frequencyTables()
    }
    deinit {
        previous = nil; channels = nil
        if let subscription { Unmanaged<CFTypeRef>.fromOpaque(subscription).release() }
        if let library { dlclose(library) }
    }

    func sample() -> CPUFrequencyMetrics {
        var result = CPUFrequencyMetrics()
        guard let api, let subscription, let channels,
              let sample = api.samples(subscription, channels, nil)?.takeRetainedValue() else {
            previous = nil; result.note = unavailableReason; return result
        }
        defer { previous = sample }
        guard let previous, let delta = api.delta(previous, sample, nil)?.takeRetainedValue() else {
            result.note = "Waiting for a second CPU frequency sample."; return result
        }
        let list = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] ?? []
        var totals: [String: (sum: Double, active: Double)] = [:]
        for value in list {
            let channel = unsafeBitCast(value, to: CFDictionary.self)
            guard api.format(channel) == 2, let subgroup = api.subgroup(channel)?.takeUnretainedValue() as String?, subgroup == "CPU Complex Performance States",
                  let name = api.name(channel)?.takeUnretainedValue() as String? else { continue }
            let family: String
            if name == "ECPU" || name.hasPrefix("ECPU") && name.dropFirst(4).allSatisfy(\.isNumber) { family = "E" }
            else if name == "PCPU" || name.hasPrefix("PCPU") && name.dropFirst(4).allSatisfy(\.isNumber) { family = "P" }
            else { continue } // CPM channels describe fabric rather than CPU execution.
            let count = api.count(channel)
            guard count > 1, count < 256, let table = tables[family] else { continue }
            let states = (0..<count).map { index in
                (name: api.stateName(channel, index)?.takeUnretainedValue() as String? ?? "", residency: api.residency(channel, index))
            }
            guard let weighted = FrequencyMath.weighted(states: states, mhz: table) else { continue }
            let old = totals[family] ?? (0, 0)
            totals[family] = (old.sum + weighted.sum, old.active + weighted.active)
        }
        if let total = totals["P"] { result.performanceMHz = total.sum / total.active }
        if let total = totals["E"] { result.efficiencyMHz = total.sum / total.active }
        if totals.isEmpty { result.note = "No active CPU residency with a matching frequency table. Experimental counters may be unsupported or idle." }
        return result
    }

    private static func frequencyTables() -> [String: [Double]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: [Double]] = [:]
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            for (family, candidates) in [("E", ["voltage-states1-sram", "voltage-states22-sram", "voltage-states23-sram"]), ("P", ["voltage-states5-sram"])] where result[family] == nil {
                for key in candidates {
                    guard let data = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                          let table = FrequencyMath.decodeTable(data) else { continue }
                    result[family] = table; break
                }
            }
        }
        return result
    }
}
