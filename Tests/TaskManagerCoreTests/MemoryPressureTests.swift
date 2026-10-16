import Testing
@testable import TaskManagerCore

struct MemoryPressureTests {
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
