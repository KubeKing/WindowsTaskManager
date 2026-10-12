import Foundation
import Testing
@testable import TaskManagerCore

struct GPUSamplerTests {
    @Test func readsDriverCountersWithoutInventingWindowsEngines() {
        let gpu = GPUSampler.decode(id: "gpu:1", name: "Apple M5", statistics: [
            "Device Utilization %": 98, "Renderer Utilization %": 94, "Tiler Utilization %": 10,
            "In use system memory": UInt64(8_450_113_536), "Alloc system memory": UInt64(10_701_275_136)
        ])
        #expect(gpu.utilization == 98)
        #expect(gpu.rendererUtilization == 94)
        #expect(gpu.tilerUtilization == 10)
        #expect(gpu.memoryInUseBytes == 8_450_113_536)
        #expect(gpu.memoryAllocatedBytes == 10_701_275_136)
    }
    @Test func missingAndInvalidCountersStayUnavailable() {
        let gpu = GPUSampler.decode(id: "gpu:1", name: "GPU", statistics: [
            "Device Utilization %": -1, "Renderer Utilization %": 101, "Tiler Utilization %": Double.nan,
            "In use system memory": -100, "Alloc system memory": "1234"
        ])
        #expect(gpu.utilization == nil)
        #expect(gpu.rendererUtilization == nil)
        #expect(gpu.tilerUtilization == nil)
        #expect(gpu.memoryInUseBytes == nil)
        #expect(gpu.memoryAllocatedBytes == nil)
        let missing = GPUSampler.decode(id: "none", name: "GPU", statistics: [:])
        #expect(missing.utilization == nil)
        #expect(missing.memoryInUseBytes == nil)
    }
    @Test func genuineZeroIsAvailableAndBooleansAreRejected() {
        let gpu = GPUSampler.decode(id: "gpu:1", name: "GPU", statistics: [
            "Device Utilization %": 0, "Renderer Utilization %": true,
            "In use system memory": 0, "Alloc system memory": false
        ])
        #expect(gpu.utilization == 0)
        #expect(gpu.rendererUtilization == nil)
        #expect(gpu.memoryInUseBytes == 0)
        #expect(gpu.memoryAllocatedBytes == nil)
    }
    @Test func gpuHistoryPreservesDeviceIdentityAndMissingSamples() {
        var snapshot = SystemSnapshot()
        snapshot.gpus = [GPUSampler.decode(id: "gpu:1", name: "GPU", statistics: ["Device Utilization %": 42])]
        let point = HistoryPoint(snapshot: snapshot)
        #expect(point.gpuByID["gpu:1"]?.utilization == 42)
        #expect(HistoryPoint(snapshot: SystemSnapshot()).gpuByID.isEmpty)
    }
    @Test func liveSamplerCarriesAvailableDriverMetricsIntoHistory() {
        let driver = GPUSampler()
        let direct = driver.sample()
        let snapshot = SystemSampler().sample()
        // A driver without this registry schema is supported through explicit nil readings.
        if direct.contains(where: { $0.utilization != nil }) {
            #expect(snapshot.gpus.contains(where: { $0.utilization != nil }))
            #expect(!HistoryPoint(snapshot: snapshot).gpuByID.isEmpty)
        }
        for gpu in snapshot.gpus {
            if let utilization = gpu.utilization { #expect((0...100).contains(utilization)) }
        }
    }
}
