import Foundation
import Testing
@testable import TaskManagerCore

struct TemperatureGraphPreferencesTests {
    @Test func cpuAndGPUChoicesPersistIndependently() {
        let name = "TaskManagerTests.TemperatureGraphs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = TemperatureGraphPreferences(defaults: defaults)
        #expect(!settings.cpu && !settings.gpu)
        settings.cpu = true
        settings.save(defaults)
        let cpuOnly = TemperatureGraphPreferences(defaults: defaults)
        #expect(cpuOnly.cpu && !cpuOnly.gpu)
        settings.cpu = false
        settings.gpu = true
        settings.save(defaults)
        let gpuOnly = TemperatureGraphPreferences(defaults: defaults)
        #expect(!gpuOnly.cpu && gpuOnly.gpu)
    }

    @Test func sharedPreferenceMigratesWithoutOverwritingSeparateChoices() {
        let name = "TaskManagerTests.TemperatureGraphs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "showTemperatures.v1")
        var settings = TemperatureGraphPreferences(defaults: defaults)
        #expect(settings.cpu && settings.gpu)
        settings.gpu = false
        settings.save(defaults)
        let restored = TemperatureGraphPreferences(defaults: defaults)
        #expect(restored.cpu && !restored.gpu)
        defaults.set(false, forKey: "showTemperatures.v1")
        #expect(TemperatureGraphPreferences(defaults: defaults).cpu)
    }
}
