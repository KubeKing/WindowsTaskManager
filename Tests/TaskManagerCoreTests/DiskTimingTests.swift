import Foundation
import Testing
@testable import TaskManagerCore

struct DiskTimingTests {
    @Test func weightsCompletedReadAndWriteDurationsInMilliseconds() {
        let old = DiskTiming(reads: 1_000, writes: 2_000, readNanoseconds: 900_000_000, writeNanoseconds: 800_000_000)
        let new = DiskTiming(reads: 1_002, writes: 2_001, readNanoseconds: 904_000_000, writeNanoseconds: 805_000_000)
        #expect(DiskTiming.responseMilliseconds(current: new, previous: old) == 3)
        // Overlapping request times can exceed wall time: this is mean request
        // duration, never a clamped or guessed disk active percentage.
        let long = DiskTiming(reads: 1_001, writes: 2_000, readNanoseconds: 2_900_000_000, writeNanoseconds: 800_000_000)
        #expect(DiskTiming.responseMilliseconds(current: long, previous: old) == 2_000)
    }
    @Test func missingBaselineResetsAndNoCompletedIOAreUnavailable() {
        let value = DiskTiming(reads: 10, writes: 5, readNanoseconds: 100, writeNanoseconds: 50)
        #expect(DiskTiming.responseMilliseconds(current: value, previous: nil) == nil)
        #expect(DiskTiming.responseMilliseconds(current: nil, previous: value) == nil)
        #expect(DiskTiming.responseMilliseconds(current: value, previous: value) == nil)
        let reset = DiskTiming(reads: 1, writes: 5, readNanoseconds: 10, writeNanoseconds: 50)
        #expect(DiskTiming.responseMilliseconds(current: reset, previous: value) == nil)
        let inconsistent = DiskTiming(reads: 10, writes: 5, readNanoseconds: 200, writeNanoseconds: 50)
        #expect(DiskTiming.responseMilliseconds(current: inconsistent, previous: value) == nil)
    }
    @Test func zeroDurationIsAvailableOnlyWithCompletedOperations() {
        let old = DiskTiming(reads: 0, writes: 0, readNanoseconds: 0, writeNanoseconds: 0)
        let new = DiskTiming(reads: 1, writes: 0, readNanoseconds: 0, writeNanoseconds: 0)
        #expect(DiskTiming.responseMilliseconds(current: new, previous: old) == 0)
    }
    @Test func requiresCompleteValidDriverTimingCounters() {
        let valid: [String: Any] = ["Operations (Read)": 2, "Operations (Write)": 3, "Total Time (Read)": 400, "Total Time (Write)": 500]
        #expect(DiskTiming.decode(valid)?.readNanoseconds == 400)
        #expect(DiskTiming.decode([:]) == nil)
        for bad in [NSNumber(value: -1), NSNumber(value: true), NSNumber(value: 1.5), NSNumber(value: Double.nan)] {
            var changed = valid; changed["Total Time (Write)"] = bad
            #expect(DiskTiming.decode(changed) == nil)
        }
    }
}
