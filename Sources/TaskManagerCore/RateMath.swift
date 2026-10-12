import Foundation

/// Counter deltas deliberately return nil on the first observation, resets, and invalid time.
enum RateMath {
    static func nanoseconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> UInt64? {
        guard numerator > 0, denominator > 0 else { return nil }
        let product = ticks.multipliedFullWidth(by: UInt64(numerator))
        guard product.high < UInt64(denominator) else { return nil }
        return UInt64(denominator).dividingFullWidth(product).quotient
    }

    static func rate(current: UInt64, previous: UInt64?, elapsed: Double) -> Double? {
        guard let previous, current >= previous, elapsed.isFinite, elapsed > 0 else { return nil }
        let value = Double(current - previous) / elapsed
        return value.isFinite ? value : nil
    }

    static func cpuPercent(current: UInt64, previous: UInt64?, elapsed: Double, logicalCPUs: Int) -> Double? {
        guard logicalCPUs > 0, let rate = rate(current: current, previous: previous, elapsed: elapsed) else { return nil }
        return min(100, max(0, rate / 1_000_000_000 / Double(logicalCPUs) * 100))
    }
}
