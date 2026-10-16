import Foundation

/// CPU and GPU overlays have separate durable choices. The former shared
/// preference only supplies the initial value when a new choice is missing.
public struct TemperatureGraphPreferences {
    public var cpu: Bool
    public var gpu: Bool

    public init(defaults: UserDefaults) {
        let shared = defaults.bool(forKey: "showTemperatures.v1")
        cpu = defaults.object(forKey: "showCPUTemperatureGraph.v1") as? Bool ?? shared
        gpu = defaults.object(forKey: "showGPUTemperatureGraph.v1") as? Bool ?? shared
    }

    public func save(_ defaults: UserDefaults) {
        defaults.set(cpu, forKey: "showCPUTemperatureGraph.v1")
        defaults.set(gpu, forKey: "showGPUTemperatureGraph.v1")
    }
}
