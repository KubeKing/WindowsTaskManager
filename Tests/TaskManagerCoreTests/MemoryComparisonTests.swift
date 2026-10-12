import Testing
@testable import TaskManagerCore

struct MemoryComparisonTests {
    @Test func comparisonUsesInUseMemoryAndDoesNotAddSharedAllocations() {
        var snapshot = fixture()
        snapshot.gpus[0].memoryAllocatedBytes = 30
        let comparison = HistoryPoint(snapshot: snapshot).memoryComparison(gpuID: "selected")
        #expect(comparison.totalBytes == 32)
        #expect(comparison.systemUsedBytes == 20)
        #expect(comparison.gpuUsedBytes == 6)
        #expect(comparison.cpuOtherEstimateBytes == 14)
    }
    @Test func unavailableGPUIsNotTreatedAsZero() {
        var snapshot = fixture()
        snapshot.gpus[0].memoryInUseBytes = nil
        let comparison = HistoryPoint(snapshot: snapshot).memoryComparison(gpuID: "selected")
        #expect(comparison.gpuUsedBytes == nil)
        #expect(comparison.cpuOtherEstimateBytes == nil)
        #expect(comparison.systemUsedBytes == 20)
        #expect(HistoryPoint(snapshot: snapshot).memoryComparison(gpuID: "missing").gpuUsedBytes == nil)
    }
    @Test func genuineZeroRemainsAvailable() {
        var snapshot = fixture()
        snapshot.gpus[0].memoryInUseBytes = 0
        let comparison = HistoryPoint(snapshot: snapshot).memoryComparison(gpuID: "selected")
        #expect(comparison.gpuUsedBytes == 0)
        #expect(comparison.cpuOtherEstimateBytes == 20)
    }
    @Test func unavailableSystemMemoryDoesNotCreateAnEstimate() {
        var snapshot = fixture()
        snapshot.memory.usageAvailable = false
        let comparison = HistoryPoint(snapshot: snapshot).memoryComparison(gpuID: "selected")
        #expect(comparison.totalBytes == 32)
        #expect(comparison.systemUsedBytes == nil)
        #expect(comparison.gpuUsedBytes == 6)
        #expect(comparison.cpuOtherEstimateBytes == nil)
    }
    @Test func inconsistentCountersDoNotUnderflowOrInventAnEstimate() {
        let tooMuchGPU = UnifiedMemoryComparison(totalBytes: 32, systemUsedBytes: 20, gpuUsedBytes: 21)
        #expect(tooMuchGPU.cpuOtherEstimateBytes == nil)
        let invalidSystem = UnifiedMemoryComparison(totalBytes: 32, systemUsedBytes: 40, gpuUsedBytes: 6)
        #expect(invalidSystem.cpuOtherEstimateBytes == nil)
        let noCapacity = UnifiedMemoryComparison(totalBytes: 0, systemUsedBytes: 20, gpuUsedBytes: 6)
        #expect(noCapacity.totalBytes == nil)
        #expect(noCapacity.cpuOtherEstimateBytes == nil)
    }
    @Test func historyKeepsPerSampleBytesAndSelectedGPUIdentity() {
        var snapshot = fixture()
        var other = GPUMetrics(id: "other", name: "Other")
        other.memoryInUseBytes = 4
        snapshot.gpus.append(other)
        let history = HistoryPoint(snapshot: snapshot)
        snapshot.memory.usedBytes = 25
        #expect(history.systemUsedMemoryBytes == 20)
        #expect(history.totalMemoryBytes == 32)
        #expect(history.memoryComparison(gpuID: "selected").cpuOtherEstimateBytes == 14)
        #expect(history.memoryComparison(gpuID: "other").cpuOtherEstimateBytes == 16)
        #expect(history.memoryComparison(gpuID: nil).cpuOtherEstimateBytes == nil)
    }
    private func fixture() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.memory.usageAvailable = true
        snapshot.memory.totalBytes = 32
        snapshot.memory.usedBytes = 20
        var gpu = GPUMetrics(id: "selected", name: "GPU")
        gpu.memoryInUseBytes = 6
        snapshot.gpus = [gpu]
        return snapshot
    }
}
