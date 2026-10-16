import Foundation
import Testing
@testable import TaskManagerCore

struct TemperaturePresentationTests {
    @Test func fixedTicksAndPositionsUseTwentyAsTheBaseline() {
        #expect(TemperatureScale.ticks == [20, 40, 60, 80, 100])
        for (index, tick) in TemperatureScale.ticks.enumerated() {
            #expect(TemperatureScale.position(tick) == Double(index) / 4)
        }
        #expect(TemperatureScale.position(10) == 0)
        #expect(TemperatureScale.position(115) == 1)
        #expect(TemperatureScale.position(.nan) == nil)
    }
    @Test func temperatureThresholdsDoNotClaimActualThrottling() {
        for (value, band): (Double, TemperatureBand) in [(20,.safe),(59.9,.safe),(60,.warm),(79.9,.warm),(80,.hot),(99.9,.hot),(100,.throttlingRisk),(115,.throttlingRisk)] {
            #expect(TemperatureBand.classify(value, pressure: .nominal) == band)
        }
        #expect(TemperatureBand.classify(110)?.label == "Throttling risk")
        #expect(TemperatureBand.classify(nil, pressure: .critical) == nil)
        #expect(TemperatureBand.classify(.nan) == nil)
        #expect(TemperatureBand.classify(150) == nil)
    }
    @Test func macOSThermalLimitingOverridesBandsWithoutRecoloringOlderSamples() {
        var snapshot = SystemSnapshot()
        snapshot.temperatures.cpuAverageCelsius = 55
        snapshot.temperatures.thermalPressure = .nominal
        let first = HistoryPoint(snapshot: snapshot)
        snapshot.temperatures.thermalPressure = .serious
        let second = HistoryPoint(snapshot: snapshot)
        #expect(TemperatureBand.classify(first.temperatures.cpuAverageCelsius, pressure: first.temperatures.thermalPressure) == .safe)
        #expect(TemperatureBand.classify(second.temperatures.cpuAverageCelsius, pressure: second.temperatures.thermalPressure) == .thermalThrottling)
        #expect(TemperatureBand.classify(55, pressure: .critical) == .thermalThrottling)
        #expect(TemperatureBand.classify(55, pressure: .fair) == .safe)
    }
}
