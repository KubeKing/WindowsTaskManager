import Foundation

/// Visibility uses persistent device identity, separate from live counter/history identity.
public struct PerformanceItem: Identifiable, Equatable {
    public var id: String
    public var preferenceID: String
    public var title: String
    public init(id: String, preferenceID: String, title: String) {
        self.id = id; self.preferenceID = preferenceID; self.title = title
    }
}

public enum PerformanceCatalog {
    public static func items(in snapshot: SystemSnapshot) -> [PerformanceItem] {
        var items = [PerformanceItem(id: "cpu", preferenceID: "cpu", title: "CPU"),
                     PerformanceItem(id: "memory", preferenceID: "memory", title: "Memory")]
        items += snapshot.disks.map { disk in
            PerformanceItem(id: "disk:" + disk.id, preferenceID: "disk:" + (disk.preferenceID ?? disk.id),
                            title: disk.name + (disk.bsdName.map { " (" + $0 + ")" } ?? ""))
        }
        items += snapshot.networks.map { PerformanceItem(id: "network:" + $0.id, preferenceID: "network:" + $0.id, title: $0.name) }
        if snapshot.gpus.isEmpty { items.append(PerformanceItem(id: "gpu", preferenceID: "gpu:default", title: "GPU 0")) }
        else {
            items += snapshot.gpus.enumerated().map { index, gpu in
                PerformanceItem(id: "gpu:" + gpu.id, preferenceID: "gpu:" + (gpu.preferenceID ?? gpu.id), title: "GPU \(index) · \(gpu.name)")
            }
        }
        return items
    }
}

/// A version-independent defaults key survives replacing/updating the app bundle.
/// Disconnected device choices are retained so reconnecting does not unhide them.
public struct PerformanceVisibility {
    public private(set) var hiddenIDs: Set<String>
    private let defaults: UserDefaults
    private static let key = "hiddenPerformanceItems.v1"
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        hiddenIDs = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }
    public func isShown(_ item: PerformanceItem) -> Bool { !hiddenIDs.contains(item.preferenceID) }
    public func visibleItems(in items: [PerformanceItem]) -> [PerformanceItem] { items.filter(isShown) }
    public func selection(_ selected: String, in items: [PerformanceItem]) -> String? {
        let visible = visibleItems(in: items)
        return visible.contains { $0.id == selected } ? selected : visible.first?.id
    }
    public mutating func setShown(_ shown: Bool, preferenceID: String) {
        if shown { hiddenIDs.remove(preferenceID) } else { hiddenIDs.insert(preferenceID) }
        defaults.set(hiddenIDs.sorted(), forKey: Self.key)
    }
    public mutating func showAll() {
        hiddenIDs.removeAll()
        defaults.removeObject(forKey: Self.key)
    }
}
