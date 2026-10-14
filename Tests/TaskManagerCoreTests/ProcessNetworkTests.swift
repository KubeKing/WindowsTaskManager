import Foundation
import Testing
@testable import TaskManagerCore

struct ProcessNetworkTests {
    private let app = NetworkProcessKey(pid: 42, uniqueID: 123)
    @Test func firstObservationIsBaselineAndFlowsAggregateWithoutLifetimeSpikes() {
        var state = NetworkFlowAccumulator()
        state.observe(source: 1, counter: .init(process: app, received: 1_000_000, sent: 100, time: 0))
        #expect(state.drain(now: 0, elapsed: 1).isEmpty)
        state.observe(source: 1, counter: .init(process: app, received: 1_000_200, sent: 140, time: 2))
        state.observe(source: 2, counter: .init(process: app, received: 500, sent: 50, time: 1))
        state.observe(source: 2, counter: .init(process: app, received: 560, sent: 70, time: 2))
        let rates = state.drain(now: 2, elapsed: 2)
        #expect(rates[app]?.received == 130)
        #expect(rates[app]?.sent == 30)
        #expect(state.drain(now: 3, elapsed: 1)[app]?.received == 0)
    }
    @Test func closedFlowsRetainTheirFinalObservedDeltaOnlyUntilDrain() {
        var state = NetworkFlowAccumulator()
        state.observe(source: 1, counter: .init(process: app, received: 10, sent: 0, time: 0))
        state.observe(source: 1, counter: .init(process: app, received: 30, sent: 4, time: 1))
        state.remove(source: 1)
        #expect(state.drain(now: 1, elapsed: 1)[app]?.received == 20)
        #expect(state.drain(now: 2, elapsed: 1).isEmpty)
    }
    @Test func resetsAndReusedProcessIDsRebaselineRatherThanMisattribute() {
        var state = NetworkFlowAccumulator()
        state.observe(source: 1, counter: .init(process: app, received: 100, sent: 50, time: 0))
        state.observe(source: 1, counter: .init(process: app, received: 1, sent: 1, time: 1))
        #expect(state.drain(now: 1, elapsed: 1).isEmpty)
        let reused = NetworkProcessKey(pid: 42, uniqueID: 456)
        state.observe(source: 1, counter: .init(process: reused, received: 500, sent: 20, time: 2))
        #expect(state.drain(now: 2, elapsed: 1).isEmpty)
        state.observe(source: 1, counter: .init(process: reused, received: 520, sent: 22, time: 3))
        let rates = state.drain(now: 3, elapsed: 1)
        #expect(rates[app] == nil)
        #expect(rates[reused]?.received == 20)
    }
    @Test func staleOrInvalidSamplingDoesNotFabricateZeros() {
        var state = NetworkFlowAccumulator()
        state.observe(source: 1, counter: .init(process: app, received: 1, sent: 1, time: 0))
        state.observe(source: 1, counter: .init(process: app, received: 2, sent: 2, time: 1))
        #expect(state.drain(now: 1, elapsed: 0).isEmpty)
        #expect(state.drain(now: 100, elapsed: 1).isEmpty)
    }
    @Test func decodingRequiresByteCountersAndKernelProcessIdentity() {
        let valid: NSDictionary = ["provider": "TCP", "processID": 42, "uniqueProcessID": 123, "rxBytes": 100, "txBytes": 50]
        #expect(ProcessNetworkSampler.decode(valid, now: 1)?.process == app)
        #expect(ProcessNetworkSampler.decode(["provider": "UDP", "processID": 42, "rxBytes": 100, "txBytes": 50], now: 1) == nil)
        #expect(ProcessNetworkSampler.decode(["provider": "unknown", "processID": 42, "uniqueProcessID": 123, "rxBytes": 100, "txBytes": 50], now: 1) == nil)
        for bad in [NSNumber(value: true), NSNumber(value: -1), NSNumber(value: 1.5), NSNumber(value: Double.infinity)] {
            let malformed = valid.mutableCopy() as! NSMutableDictionary
            malformed["rxBytes"] = bad
            #expect(ProcessNetworkSampler.decode(malformed, now: 1) == nil)
        }
    }
    @Test func flowLimitFailsUnavailableInsteadOfReportingPartialTotals() {
        var state = NetworkFlowAccumulator()
        for source in 0...16_384 {
            state.observe(source: UInt(source), counter: .init(process: app, received: 0, sent: 0, time: 0))
        }
        state.observe(source: 1, counter: .init(process: app, received: 100, sent: 0, time: 1))
        #expect(state.overflowed)
        #expect(state.drain(now: 1, elapsed: 1).isEmpty)
    }
}
