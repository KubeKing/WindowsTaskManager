import Foundation
import Testing
@testable import TaskManagerCore

struct SamplerTests {
    @Test func diskInventoryDoesNotPresentAnonymousDriversAsPhysicalDisks() {
        let disks = SystemSampler().sample().disks
        #expect(!disks.contains { $0.name.hasPrefix("Physical disk ") })
    }
    @Test func firstObservationHasNoRate() {
        #expect(RateMath.rate(current: 100, previous: nil, elapsed: 1) == nil)
    }
    @Test func counterResetHasNoRate() {
        #expect(RateMath.rate(current: 2, previous: 100, elapsed: 1) == nil)
    }
    @Test func rateUsesMonotonicElapsed() {
        #expect(RateMath.rate(current: 300, previous: 100, elapsed: 2) == 100)
    }
    @Test func invalidElapsedHasNoRate() {
        for elapsed in [0.0, -1, Double.nan, Double.infinity] {
            #expect(RateMath.rate(current: 300, previous: 100, elapsed: elapsed) == nil)
        }
    }
    @Test func cpuUsesWholeMachineNormalization() {
        #expect(RateMath.cpuPercent(current: 3_000_000_000, previous: 1_000_000_000, elapsed: 1, logicalCPUs: 4) == 50)
        #expect(RateMath.cpuPercent(current: 1, previous: 0, elapsed: 1, logicalCPUs: 0) == nil)
    }
    @Test func machTicksConvertBeforeCPUNormalization() {
        #expect(RateMath.nanoseconds(ticks: 4_800_000, numerator: 125, denominator: 3) == 200_000_000)
        #expect(RateMath.nanoseconds(ticks: 10, numerator: 1, denominator: 1) == 10)
        #expect(RateMath.nanoseconds(ticks: 10, numerator: 1, denominator: 0) == nil)
    }
    @Test func cpuPercentIsBounded() {
        #expect(RateMath.cpuPercent(current: 10_000_000_000, previous: 0, elapsed: 1, logicalCPUs: 1) == 100)
    }
    @Test func liveSamplerReportsCurrentProcessAndValidMemory() {
        let sampler = SystemSampler()
        let first = sampler.sample()
        let current = first.processes.first { $0.id.pid == ProcessInfo.processInfo.processIdentifier }
        #expect(current != nil)
        #expect(current?.id == SystemSampler.identity(pid: ProcessInfo.processInfo.processIdentifier))
        #expect(current?.cpuPercent == nil)
        #expect(current?.status != nil)
        #expect(first.cpuKernelUsage == nil)
        #expect(first.memory.totalBytes > 0)
        #expect(first.memory.usageAvailable)
        #expect(first.memory.usedBytes <= first.memory.totalBytes)
        Thread.sleep(forTimeInterval: 0.12)
        let next = sampler.sample()
        #expect(next.cpuUsage != nil)
        #expect(!next.logicalCPUUsage.isEmpty)
        #expect(next.logicalKernelUsage.count == next.logicalCPUUsage.count)
        #expect((next.cpuKernelUsage ?? -1) >= 0)
        #expect((next.cpuKernelUsage ?? 100) <= (next.cpuUsage ?? 0))
        #expect(next.memory.cachedBytes != nil)
        #expect(next.memory.freeBytes != nil)
        #expect(next.monotonicTime > first.monotonicTime)
        print("LIVE SAMPLE processes=\(next.processes.count) CPU=\(next.cpuUsage ?? -1) memory=\(next.memory.usedBytes)/\(next.memory.totalBytes) network=\(next.networks.map(\.id)) disks=\(next.disks.map(\.mountPath)) duration=\(next.collectionDuration) warnings=\(next.warnings)")
    }
}
