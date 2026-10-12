import Foundation

/// Graphable metrics, with units and unavailable Windows engine concepts kept explicit.
public enum GPUChartMetric: String, CaseIterable, Identifiable, Sendable {
    case utilization, renderer, tiler, memoryInUse, memoryAllocated, videoDecode, videoEncode, copy
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .utilization: return "GPU utilization"
        case .renderer: return "Renderer"
        case .tiler: return "Tiler"
        case .memoryInUse: return "GPU memory in use"
        case .memoryAllocated: return "GPU memory allocated"
        case .videoDecode: return "Video Decode"
        case .videoEncode: return "Video Encode"
        case .copy: return "Copy"
        }
    }
    public var isMemory: Bool { self == .memoryInUse || self == .memoryAllocated }
    public func value(in gpu: GPUMetrics?) -> Double? {
        switch self {
        case .utilization: return gpu?.utilization
        case .renderer: return gpu?.rendererUtilization
        case .tiler: return gpu?.tilerUtilization
        case .memoryInUse: return gpu?.memoryInUseBytes.map { Double($0) }
        case .memoryAllocated: return gpu?.memoryAllocatedBytes.map { Double($0) }
        case .videoDecode, .videoEncode, .copy: return nil
        }
    }
    public var unavailableReason: String {
        switch self {
        case .videoDecode, .videoEncode, .copy:
            return "No validated separate \(title.lowercased()) percentage is available on this Mac."
        default: return "This driver counter is unavailable."
        }
    }
}

/// Slot identities are stable even while their selected metric changes. Preferences
/// are independent of the app version and do not store live registry identifiers.
public struct GPUChartLayout {
    public static let defaults: [GPUChartMetric] = [.utilization, .renderer, .tiler, .memoryInUse]
    public private(set) var metrics: [GPUChartMetric]
    private let defaultsStore: UserDefaults
    private static let key = "gpuChartMetrics.v1"
    public init(defaults: UserDefaults) {
        defaultsStore = defaults
        let saved = defaults.stringArray(forKey: Self.key) ?? []
        metrics = Self.defaults.enumerated().map { slot, fallback in
            saved.indices.contains(slot) ? GPUChartMetric(rawValue: saved[slot]) ?? fallback : fallback
        }
    }
    public mutating func set(_ metric: GPUChartMetric, at slot: Int) {
        guard metrics.indices.contains(slot) else { return }
        metrics[slot] = metric
        defaultsStore.set(metrics.map(\.rawValue), forKey: Self.key)
    }
}
