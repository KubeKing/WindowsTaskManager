import Foundation
import Testing
@testable import TaskManagerCore

struct HardwareInfoTests {
    @Test func coreKindsFollowLogicalIDsRatherThanEnumerationOrder() {
        let kinds = CPUCoreTopology.kinds(entries: [(2, Data([80, 0])), (0, Data([69, 0]))], logicalCount: 3)
        #expect(kinds[0] == .efficiency)
        #expect(kinds[2] == .performance)
        #expect(kinds[1] == nil)
    }
    @Test func coreKindsDoNotGuessMissingMalformedOrConflictingMappings() {
        let kinds = CPUCoreTopology.kinds(entries: [(0, Data([69, 0])), (0, Data([80, 0])), (1, Data([77, 0])), (2, Data([80])), (9, Data([80, 0]))], logicalCount: 3)
        #expect(kinds.isEmpty)
    }
    @Test func hardwareSnapshotHasRealCoreCountsAndStableIdentity() {
        let hardware = HardwareInfo.read()
        #expect(hardware.physicalCPUs > 0)
        #expect(hardware.logicalCPUs >= hardware.physicalCPUs)
        #expect(!hardware.cpuName.isEmpty)
        #expect(!hardware.model.isEmpty)
        #expect(!hardware.gpuName.isEmpty)
        #expect(hardware.cpuName == HardwareInfo.read().cpuName)
    }
    @Test func historyPreservesKernelAndPerDeviceMeasurements() {
        var snapshot = SystemSnapshot()
        snapshot.cpuKernelUsage = 5
        snapshot.logicalKernelUsage = [2, 8]
        var network = NetworkMetrics(id: "en0", name: "Wi-Fi")
        network.receiveBytesPerSecond = 500
        snapshot.networks = [network]
        var disk = DiskMetrics(id: "io:1", name: "SSD", mountPath: "Device I/O")
        disk.readBytesPerSecond = 700
        snapshot.disks = [disk]
        let history = HistoryPoint(snapshot: snapshot)
        #expect(history.kernelCPU == 5)
        #expect(history.logicalKernel == [2, 8])
        #expect(history.networkByID["en0"]?.receiveBytesPerSecond == 500)
        #expect(history.diskByID["io:1"]?.readBytesPerSecond == 700)
    }
    @Test func bsdStatusesMapToRealProcessStates() {
        #expect(SystemSampler.statusLabel(1) == "Idle")
        #expect(SystemSampler.statusLabel(2) == "Running")
        #expect(SystemSampler.statusLabel(3) == "Sleeping")
        #expect(SystemSampler.statusLabel(4) == "Stopped")
        #expect(SystemSampler.statusLabel(5) == "Zombie")
        #expect(SystemSampler.statusLabel(999) == nil)
    }
}
