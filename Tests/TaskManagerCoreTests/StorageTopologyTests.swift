import Foundation
import Testing
@testable import TaskManagerCore

struct StorageTopologyTests {
    @Test func joinsVerifiedAPFSVolumesWithoutDoubleCountingSharedCapacity() {
        var drive = DiskMetrics(id: "io:1", name: "Internal SSD", mountPath: "Whole device")
        drive.totalBytes = 1_000; drive.bsdName = "disk0"
        let root = DiskVolume(id: "disk3s1s1", name: "Startup", mountPath: "/", totalBytes: 950, freeBytes: 600)
        let sibling = DiskVolume(id: "disk3s7", name: "Projects", mountPath: "/Volumes/Projects", totalBytes: 950, freeBytes: 600)
        let rows = StorageTopology.join(devices: [StorageDevice(metric: drive, descendantBSDNames: ["disk0", root.id, sibling.id])], volumes: [sibling, root])
        #expect(rows.count == 1)
        #expect(rows.first?.primaryVolume?.id == root.id)
        #expect(rows.first?.totalBytes == 1_000) // physical capacity, not a sum of volume capacities
        #expect(rows.first?.primaryVolume?.usedBytes == 350)
        #expect(rows.first?.volumes.count == 2)
    }
    @Test func unmatchedVolumeStaysVisibleWithoutInventingPhysicalThroughput() {
        let volume = DiskVolume(id: "disk9s1", name: "Unmapped", mountPath: "/Volumes/Unmapped", totalBytes: 100, freeBytes: 20)
        let row = StorageTopology.join(devices: [], volumes: [volume]).first
        #expect(row?.kind == .volume)
        #expect(row?.readBytesPerSecond == nil)
        #expect(row?.primaryVolume?.usedPercent == 80)
    }
    @Test func invalidCapacityCannotUnderflowOrClaimAnUnknownPercentage() {
        let volume = DiskVolume(id: "x", name: "x", mountPath: "/", totalBytes: 10, freeBytes: 20)
        #expect(volume.usedBytes == 0)
        #expect(volume.freeBytes == 10)
        #expect(DiskVolume(id: "x", name: "x", mountPath: "/", totalBytes: 0, freeBytes: 0).usedPercent == nil)
    }
    @Test func aggregateThroughputCountsPhysicalDriveOnceAndExcludesImage() {
        var snapshot = SystemSnapshot()
        var drive = DiskMetrics(id: "io:1", name: "SSD", mountPath: "Whole device")
        drive.totalBytes = 1_000; drive.readBytesPerSecond = 100
        var image = DiskMetrics(id: "io:2", name: "Disk image", mountPath: "Whole device")
        image.kind = .image; image.readBytesPerSecond = 40
        snapshot.disks = [image, drive]
        #expect(HistoryPoint(snapshot: snapshot).diskRead == 100)
        #expect(HistoryPoint(snapshot: snapshot).diskByID[image.id]?.readBytesPerSecond == 40)
    }
}
