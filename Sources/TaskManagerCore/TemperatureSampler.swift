import Foundation
import Darwin
import IOKit

public struct TemperatureMetrics: Sendable {
    public var cpuAverageCelsius: Double? = nil
    public var gpuAverageCelsius: Double? = nil
    public var cpuSensorCount = 0
    public var gpuSensorCount = 0
    // Thermal zone enumeration is never a mapping to OS logical core IDs.
    public var logicalCoreCelsius: [Int: Double] = [:]
    public var sampledAt: Date? = nil
    public var note = "Experimental average of readable Apple silicon CPU/GPU die sensors; individual-core mapping is unavailable."
    public init() {}
}

enum TemperatureCodec {
    enum Component { case cpu, gpu }
    static func component(_ name: String) -> Component? {
        guard name.utf8.count == 4 else { return nil }
        if name.hasPrefix("Tp") || name.hasPrefix("Te") { return .cpu }
        if name.hasPrefix("Tg") { return .gpu }
        return nil
    }
    static func celsius(_ bytes: Data) -> Double? {
        guard bytes.count == 4 else { return nil }
        let bits = bytes.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        let value = Double(Float(bitPattern: bits))
        return valid(value) ? value : nil
    }
    static func valid(_ value: Double) -> Bool { value.isFinite && value > 0 && value < 150 }
    static func average(_ values: [Double?]) -> (value: Double?, count: Int) {
        let values = values.compactMap { $0 }.filter(valid)
        return (values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), values.count)
    }
}

/// Read-only AppleSMC wire protocol. Only read, key-info and enumeration
/// commands exist here; no writes, fan controls, subprocesses or helper.
protocol TemperatureSource: AnyObject { func read() -> TemperatureMetrics }

private final class SMCTemperatureReader: TemperatureSource {
    private enum Command: UInt8 { case read = 5, index = 8, info = 9 }
    private var connection: io_connect_t = 0
    private var sensors: [(key: UInt32, component: TemperatureCodec.Component)] = []
    private static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private static func uint(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
    private func call(_ command: Command, key: UInt32 = 0, index: UInt32 = 0, size: UInt32 = 0) -> Data? {
        // Verified 80-byte SMC ABI: key 0, keyInfo 28, data8 42,
        // data32 44, payload 48. Reserved/padding bytes remain zero.
        var input = Data(repeating: 0, count: 80), output = Data(repeating: 0, count: 80)
        func put(_ value: UInt32, at offset: Int) { var value = value.littleEndian; withUnsafeBytes(of: &value) { input.replaceSubrange(offset..<offset+4, with: $0) } }
        put(key, at: 0); put(size, at: 28); put(index, at: 44); input[42] = command.rawValue
        var outputSize = 80
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, target.baseAddress, &outputSize)
            }
        }
        guard status == KERN_SUCCESS, outputSize == 80, output[40] == 0 else { return nil }
        return output
    }
    init?() {
        #if !arch(arm64)
        return nil
        #else
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        let status = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard status == KERN_SUCCESS else { return nil }
        guard let countData = call(.read, key: Self.code("#KEY"), size: 4) else { return nil }
        let count = countData[48..<52].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count < 16_384 else { return nil }
        for index in 0..<count {
            guard let entry = call(.index, index: index) else { continue }
            let key = Self.uint(entry, at: 0)
            let name = String(bytes: [24,16,8,0].map { UInt8(truncatingIfNeeded: key >> $0) }, encoding: .ascii) ?? ""
            guard let component = TemperatureCodec.component(name), let info = call(.info, key: key),
                  Self.uint(info, at: 28) == 4, Self.uint(info, at: 32) == Self.code("flt ") else { continue }
            sensors.append((key,component))
            guard sensors.count <= 128 else { return nil } // Fail instead of reporting a truncated average.
        }
        guard !sensors.isEmpty else { return nil }
        #endif
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    func read() -> TemperatureMetrics {
        var cpu: [Double?] = [], gpu: [Double?] = []
        for sensor in sensors {
            let value = call(.read, key: sensor.key, size: 4).flatMap { TemperatureCodec.celsius($0.subdata(in: 48..<52)) }
            if sensor.component == .cpu { cpu.append(value) } else { gpu.append(value) }
        }
        let c = TemperatureCodec.average(cpu), g = TemperatureCodec.average(gpu)
        var result = TemperatureMetrics()
        result.cpuAverageCelsius = c.value; result.cpuSensorCount = c.count
        result.gpuAverageCelsius = g.value; result.gpuSensorCount = g.count
        result.sampledAt = Date()
        return result
    }
}

/// Created only when enabled. Reads cached discovered keys at most every two
/// seconds; unavailable connections retry once per minute, not every UI tick.
final class TemperatureSampler {
    private var reader: TemperatureSource?
    private let makeReader: () -> TemperatureSource?
    init(makeReader: @escaping () -> TemperatureSource? = { SMCTemperatureReader() }) { self.makeReader = makeReader }
    private var lastAttempt = -Double.infinity
    private var lastRead = -Double.infinity
    private var cached = TemperatureMetrics()
    func sample(now: Double) -> TemperatureMetrics {
        if now - lastRead < 2 { return cached }
        if reader == nil {
            guard now - lastAttempt >= 60 else { return cached }
            lastAttempt = now; reader = makeReader()
        }
        lastRead = now
        guard let reader else {
            cached = TemperatureMetrics(); cached.note = "Native temperature sensors are unavailable on this Mac; no administrator helper is installed."
            return cached
        }
        cached = reader.read()
        if cached.cpuAverageCelsius == nil && cached.gpuAverageCelsius == nil {
            self.reader = nil; lastAttempt = now
        }
        return cached
    }
}
