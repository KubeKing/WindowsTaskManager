import Foundation

/// IOBlockStorageDriver timing is per completed request, not non-overlapping busy
/// residency. Summing request durations cannot establish a disk active percentage.
struct DiskTiming {
    var reads: UInt64
    var writes: UInt64
    var readNanoseconds: UInt64
    var writeNanoseconds: UInt64
    static func decode(_ statistics: [String: Any]) -> DiskTiming? {
        func counter(_ key: String) -> UInt64? {
            guard let number = statistics[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let type = String(cString: number.objCType)
            if ["Q", "L", "I", "S", "C"].contains(type) { return number.uint64Value }
            if ["q", "l", "i", "s", "c"].contains(type) { return number.int64Value >= 0 ? number.uint64Value : nil }
            let value = number.doubleValue
            guard value.isFinite, value >= 0, value.rounded(.towardZero) == value,
                  value < 18_446_744_073_709_551_616.0 else { return nil }
            return UInt64(value)
        }
        guard let reads = counter("Operations (Read)"), let writes = counter("Operations (Write)"),
              let readTime = counter("Total Time (Read)"), let writeTime = counter("Total Time (Write)") else { return nil }
        return DiskTiming(reads: reads, writes: writes, readNanoseconds: readTime, writeNanoseconds: writeTime)
    }
    static func responseMilliseconds(current: DiskTiming?, previous: DiskTiming?) -> Double? {
        guard let current, let previous,
              current.reads >= previous.reads, current.writes >= previous.writes,
              current.readNanoseconds >= previous.readNanoseconds, current.writeNanoseconds >= previous.writeNanoseconds else { return nil }
        let reads = current.reads - previous.reads, writes = current.writes - previous.writes
        let readTime = current.readNanoseconds - previous.readNanoseconds, writeTime = current.writeNanoseconds - previous.writeNanoseconds
        guard (reads > 0 || readTime == 0), (writes > 0 || writeTime == 0) else { return nil }
        let operations = Double(reads) + Double(writes)
        guard operations > 0 else { return nil } // No completed I/O is not a zero-ms observation.
        return (Double(readTime) + Double(writeTime)) / operations / 1_000_000
    }
}
