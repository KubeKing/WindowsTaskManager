import Testing
@testable import TaskManagerCore

struct MemoryPressureTests {
    @Test func convertsKernelAvailableLevelToActivityMonitorPressure() {
        #expect(MemoryPressureMath.percent(availablePercent: 48) == 52)
        #expect(MemoryPressureMath.percent(availablePercent: 100) == 0)
        #expect(MemoryPressureMath.percent(availablePercent: 0) == 100)
        #expect(MemoryPressureMath.percent(availablePercent: -1) == nil)
        #expect(MemoryPressureMath.percent(availablePercent: 101) == nil)
    }

    @Test func historyRetainsGranularChangesWithinTheSamePressureState() {
        var snapshot = SystemSnapshot()
        snapshot.memory.pressure = "Normal"
        snapshot.memory.pressurePercent = 37
        let first = HistoryPoint(snapshot: snapshot)
        snapshot.memory.pressurePercent = 41
        let next = HistoryPoint(snapshot: snapshot)
        #expect(first.memoryPressure == .normal)
        #expect(next.memoryPressure == .normal)
        #expect(first.memoryPressurePercent == 37)
        #expect(next.memoryPressurePercent == 41)
        snapshot.memory.pressurePercent = nil
        #expect(HistoryPoint(snapshot: snapshot).memoryPressurePercent == nil)
    }

    @Test func recordsReportedPressureIndependentlyOfMemoryUsage() {
        var snapshot = SystemSnapshot()
        snapshot.memory.usageAvailable = true
        snapshot.memory.totalBytes = 100
        snapshot.memory.usedBytes = 95
        snapshot.memory.pressure = "Normal"
        let normal = HistoryPoint(snapshot: snapshot)
        snapshot.memory.usedBytes = 20
        snapshot.memory.pressure = "Critical"
        let critical = HistoryPoint(snapshot: snapshot)
        #expect(normal.memoryPressure == .normal)
        #expect(critical.memoryPressure == .critical)
        #expect(normal.memory == 95)
        #expect(critical.memory == 20)
    }

    @Test func historyPreservesWarningAndUnknownIsAGap() {
        var snapshot = SystemSnapshot()
        snapshot.memory.pressure = "Warning"
        let warning = HistoryPoint(snapshot: snapshot)
        snapshot.memory.pressure = "Unknown"
        #expect(warning.memoryPressure == .warning)
        #expect(HistoryPoint(snapshot: snapshot).memoryPressure == nil)
        snapshot.memory.pressure = "Unsupported value"
        #expect(HistoryPoint(snapshot: snapshot).memoryPressure == nil)
    }
}
