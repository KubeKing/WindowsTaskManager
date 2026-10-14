import Foundation
import Testing
@testable import TaskManagerCore

struct CPUFrequencyTests {
    private func table(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            var frequency = value.littleEndian, voltage: UInt32 = 0
            withUnsafeBytes(of: &frequency) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &voltage) { data.append(contentsOf: $0) }
        }
        return data
    }
    @Test func decodesHzAndKHzFrequencyTablesConsistently() {
        #expect(FrequencyMath.decodeTable(table([600_000_000, 3_000_000_000])) == [600, 3000])
        #expect(FrequencyMath.decodeTable(table([972_000, 3_048_000])) == [972, 3048])
    }
    @Test func rejectsInvalidOrUnorderedTables() {
        #expect(FrequencyMath.decodeTable(Data()) == nil)
        #expect(FrequencyMath.decodeTable(Data([1, 2, 3])) == nil)
        #expect(FrequencyMath.decodeTable(table([24_000_000])) == nil)
        #expect(FrequencyMath.decodeTable(table([3_000_000, 600_000])) == nil)
    }
    @Test func frequencyIsWeightedByActiveTimeAndIgnoresIdle() {
        let value = FrequencyMath.weighted(states: [("IDLE", 1000), ("V0P1", 1), ("V1P0", 3)], mhz: [1000, 3000])
        #expect(value?.active == 4)
        #expect(value.map { $0.sum / $0.active } == 2500)
    }
    @Test func unmatchedStateTablesAndIdleOnlyWindowsStayUnavailable() {
        #expect(FrequencyMath.weighted(states: [("IDLE", 1), ("V0P0", 0)], mhz: [1000]) == nil)
        #expect(FrequencyMath.weighted(states: [("V0P1", 1)], mhz: [1000, 2000]) == nil)
        #expect(FrequencyMath.weighted(states: [("V2P0", 1)], mhz: [1000]) == nil)
        #expect(FrequencyMath.weighted(states: [("UNKNOWN", 1)], mhz: [1000]) == nil)
    }
}
