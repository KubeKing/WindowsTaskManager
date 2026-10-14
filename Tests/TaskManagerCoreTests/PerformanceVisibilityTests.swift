import Foundation
import Testing
@testable import TaskManagerCore

struct PerformanceVisibilityTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "TaskManagerTests.Visibility.\(UUID().uuidString)")!
    }
    @Test func survivesNewInstanceAndDeviceRegistryIDChanges() {
        let defaults = defaults()
        var first = PerformanceVisibility(defaults: defaults)
        var old = SystemSnapshot()
        var disk = DiskMetrics(id: "io:123", name: "Disk", mountPath: "Device I/O")
        disk.preferenceID = "IOService:/storage/device"
        old.disks = [disk]
        let item = PerformanceCatalog.items(in: old).first { $0.id == "disk:io:123" }!
        first.setShown(false, preferenceID: item.preferenceID)
        disk.id = "io:999"; old.disks = [disk]
        let restored = PerformanceVisibility(defaults: defaults)
        let newItem = PerformanceCatalog.items(in: old).first { $0.id == "disk:io:999" }!
        #expect(!restored.isShown(newItem))
        #expect(restored.selection(newItem.id, in: PerformanceCatalog.items(in: old)) == "cpu")
    }
    @Test func disconnectedChoicesRemainHiddenAndRestoreAllWorks() {
        let defaults = defaults()
        var visibility = PerformanceVisibility(defaults: defaults)
        let item = PerformanceItem(id: "network:en9", preferenceID: "network:en9", title: "Adapter")
        visibility.setShown(false, preferenceID: item.preferenceID)
        #expect(visibility.visibleItems(in: []).isEmpty)
        #expect(!PerformanceVisibility(defaults: defaults).isShown(item))
        visibility.showAll()
        #expect(PerformanceVisibility(defaults: defaults).isShown(item))
    }
    @Test func allHiddenHasNoSelectionAndNewDevicesStartVisible() {
        let defaults = defaults()
        var visibility = PerformanceVisibility(defaults: defaults)
        let items = PerformanceCatalog.items(in: SystemSnapshot())
        for item in items { visibility.setShown(false, preferenceID: item.preferenceID) }
        #expect(visibility.selection("cpu", in: items) == nil)
        #expect(visibility.visibleItems(in: items).isEmpty)
        #expect(visibility.isShown(PerformanceItem(id: "new", preferenceID: "new", title: "New")))
        visibility.setShown(true, preferenceID: "memory")
        #expect(visibility.selection("cpu", in: items) == "memory")
    }
}
