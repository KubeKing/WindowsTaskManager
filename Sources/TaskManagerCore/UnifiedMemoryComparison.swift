import Foundation

/// A comparison of independent shared-memory counters, not a disjoint CPU/GPU allocation ledger.
public struct UnifiedMemoryComparison: Sendable {
    public let totalBytes: UInt64?
    public let systemUsedBytes: UInt64?
    public let gpuUsedBytes: UInt64?
    public let cpuOtherEstimateBytes: UInt64?

    public init(totalBytes: UInt64?, systemUsedBytes: UInt64?, gpuUsedBytes: UInt64?) {
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
        self.systemUsedBytes = systemUsedBytes
        self.gpuUsedBytes = gpuUsedBytes
        // Different counter scopes can disagree. Do not clamp disagreement into a false zero.
        if let total = self.totalBytes, let system = systemUsedBytes, let gpu = gpuUsedBytes,
           system <= total, gpu <= system {
            cpuOtherEstimateBytes = system - gpu
        } else {
            cpuOtherEstimateBytes = nil
        }
    }
}

extension HistoryPoint {
    public func memoryComparison(gpuID: String?) -> UnifiedMemoryComparison {
        UnifiedMemoryComparison(totalBytes: totalMemoryBytes, systemUsedBytes: systemUsedMemoryBytes,
                                gpuUsedBytes: gpuID.flatMap { gpuByID[$0]?.memoryInUseBytes })
    }
}
