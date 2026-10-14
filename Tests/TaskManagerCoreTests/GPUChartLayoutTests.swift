import Foundation
import Testing
@testable import TaskManagerCore

struct GPUChartLayoutTests {
    @Test func independentSlotsPersistAndUnknownEntriesFallBackSafely() {
        let domain = "TaskManagerTests.GPUCharts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var first = GPUChartLayout(defaults: defaults)
        #expect(first.metrics == GPUChartLayout.defaults)
        first.set(.memoryAllocated, at: 0)
        first.set(.renderer, at: 3) // Repeated metrics in separate slots are allowed.
        let restored = GPUChartLayout(defaults: defaults)
        #expect(restored.metrics == [.memoryAllocated, .renderer, .tiler, .renderer])
        defaults.set(["videoDecode", "future-metric", "memoryAllocated"], forKey: "gpuChartMetrics.v1")
        #expect(GPUChartLayout(defaults: defaults).metrics == [.videoDecode, .renderer, .memoryAllocated, .memoryInUse])
    }
    @Test func invalidSlotDoesNotChangeLayout() {
        let domain = "TaskManagerTests.GPUCharts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var layout = GPUChartLayout(defaults: defaults)
        layout.set(.copy, at: -1); layout.set(.copy, at: 4)
        #expect(layout.metrics == GPUChartLayout.defaults)
    }
    @Test func metricsUseTheSelectedGPUAndCorrectUnitsWithoutInventingEngines() {
        var gpu = GPUMetrics(id: "selected", name: "GPU")
        gpu.utilization = 25; gpu.rendererUtilization = 10; gpu.tilerUtilization = 0
        gpu.memoryInUseBytes = 1_000; gpu.memoryAllocatedBytes = 2_000
        #expect(GPUChartMetric.utilization.value(in: gpu) == 25)
        #expect(GPUChartMetric.tiler.value(in: gpu) == 0)
        #expect(GPUChartMetric.memoryInUse.value(in: gpu) == 1_000)
        #expect(GPUChartMetric.memoryAllocated.isMemory)
        #expect(!GPUChartMetric.renderer.isMemory)
        for metric in [GPUChartMetric.videoDecode, .videoEncode, .copy] { #expect(metric.value(in: gpu) == nil) }
        for metric in GPUChartMetric.allCases { #expect(metric.value(in: nil) == nil) }
    }
}
