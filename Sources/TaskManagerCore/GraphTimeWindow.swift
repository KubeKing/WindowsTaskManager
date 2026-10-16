import Foundation

public enum GraphTimeWindow: Double, CaseIterable, Sendable {
    case thirtySeconds = 30, oneMinute = 60, twoMinutes = 120, fiveMinutes = 300, tenMinutes = 600
    public var label: String { rawValue < 60 ? "30 seconds" : "\(Int(rawValue / 60)) minute\(rawValue == 60 ? "" : "s")" }
    public var axisLabel: String { rawValue < 60 ? "30s ago" : "\(Int(rawValue / 60))m ago" }
    public static func load(_ defaults: UserDefaults) -> Self { Self(rawValue: defaults.double(forKey: "graphTimeWindow.v1")) ?? .oneMinute }
    public func save(_ defaults: UserDefaults) { defaults.set(rawValue, forKey: "graphTimeWindow.v1") }
}

/// All charts use a fixed duration ending at the latest recorded sample, even
/// during warm-up, pauses or changes in cadence. History never sets the scale.
public struct GraphTimeline {
    public let end: Date
    public let seconds: Double
    public init(end: Date, window: GraphTimeWindow) { self.end = end; seconds = window.rawValue }
    public func position(_ date: Date) -> Double? {
        let offset = date.timeIntervalSince(end)
        guard offset.isFinite else { return nil }
        return 1 + offset / seconds
    }
}

public enum GraphHistory {
    // Ten minutes at the fastest supported cadence plus the left-edge anchor.
    public static let maximumPoints = 1_202
    public static func retained(_ points: [HistoryPoint]) -> [HistoryPoint] {
        visible(points, seconds: GraphTimeWindow.tenMinutes.rawValue).suffix(maximumPoints).map { $0 }
    }
    public static func visible(_ points: [HistoryPoint], seconds: Double) -> [HistoryPoint] {
        guard let end = points.last?.timestamp, seconds.isFinite, seconds > 0 else { return [] }
        let cutoff = end.addingTimeInterval(-seconds)
        guard let first = points.firstIndex(where: { $0.timestamp >= cutoff }) else { return [] }
        // One predecessor lets the plot intersect the left boundary correctly.
        return Array(points[max(0, first - 1)...])
    }
}
