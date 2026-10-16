import Foundation

public enum ThermalPressure: Int, Sendable {
    case nominal, fair, serious, critical, unknown
    public static func current() -> Self {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}

public enum TemperatureBand: Sendable {
    case safe, warm, hot, throttlingRisk, thermalThrottling
    public var label: String {
        switch self {
        case .safe: return "Safe"
        case .warm: return "Warm"
        case .hot: return "Hot"
        case .throttlingRisk: return "Throttling risk"
        case .thermalThrottling: return "Thermal throttling · system"
        }
    }
    public static func classify(_ celsius: Double?, pressure: ThermalPressure = .unknown) -> Self? {
        guard let celsius, TemperatureCodec.valid(celsius) else { return nil }
        // System thermal pressure is distinct from a temperature threshold.
        if pressure == .serious || pressure == .critical { return .thermalThrottling }
        if celsius >= 100 { return .throttlingRisk }
        if celsius >= 80 { return .hot }
        if celsius >= 60 { return .warm }
        return .safe
    }
}

public enum TemperatureScale {
    public static let minimum = 20.0
    public static let maximum = 100.0
    public static let ticks: [Double] = [20, 40, 60, 80, 100]
    /// Plot coordinates clamp; the numeric reading retains the actual value.
    public static func position(_ celsius: Double) -> Double? {
        guard celsius.isFinite else { return nil }
        return min(1, max(0, (celsius - minimum) / (maximum - minimum)))
    }
}
