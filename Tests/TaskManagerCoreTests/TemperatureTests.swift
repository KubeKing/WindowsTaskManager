import Foundation
import Testing
@testable import TaskManagerCore

struct TemperatureTests {
    private final class Source: TemperatureSource {
        var reads = 0
        func read() -> TemperatureMetrics { reads += 1;var value=TemperatureMetrics();value.cpuAverageCelsius=45;value.cpuSensorCount=1;return value }
    }
    @Test func sensorReadsAreThrottledAndMissingSourcesBackOff() {
        let source=Source()
        var opens=0
        let sampler=TemperatureSampler(makeReader:{ opens += 1;return source })
        #expect(sampler.sample(now:10).cpuAverageCelsius == 45)
        _ = sampler.sample(now:10.5);_ = sampler.sample(now:11.9)
        #expect(source.reads == 1 && opens == 1)
        _ = sampler.sample(now:12)
        #expect(source.reads == 2 && opens == 1)
        var attempts=0
        let unavailable=TemperatureSampler(makeReader:{ attempts += 1;return nil })
        #expect(unavailable.sample(now:0).cpuAverageCelsius == nil)
        _ = unavailable.sample(now:30);_ = unavailable.sample(now:59)
        #expect(attempts == 1)
        _ = unavailable.sample(now:60)
        #expect(attempts == 2)
    }
    @Test func decodesOnlyValidatedFourByteFiniteCelsiusReadings() {
        func bytes(_ value: Float) -> Data { var bits=value.bitPattern.littleEndian;return withUnsafeBytes(of:&bits) { Data($0) } }
        #expect(TemperatureCodec.celsius(bytes(52.5)) == 52.5)
        for invalid: Float in [0,-1,150,.infinity,.nan] { #expect(TemperatureCodec.celsius(bytes(invalid)) == nil) }
        #expect(TemperatureCodec.celsius(Data([0,1])) == nil)
    }
    @Test func averagesOnlyReadableSensorsAndNeverAssignsThemToCores() {
        let average=TemperatureCodec.average([40,nil,60,.nan,-1,160])
        #expect(average.value == 50 && average.count == 2)
        #expect(TemperatureCodec.average([nil,0,.nan]).value == nil)
        #expect(TemperatureMetrics().logicalCoreCelsius.isEmpty)
        #expect(TemperatureCodec.component("Tp0a") == .cpu)
        #expect(TemperatureCodec.component("Te01") == .cpu)
        #expect(TemperatureCodec.component("Tg0U") == .gpu)
        #expect(TemperatureCodec.component("TB0T") == nil)
        #expect(TemperatureCodec.component("Tp012") == nil)
    }
}
