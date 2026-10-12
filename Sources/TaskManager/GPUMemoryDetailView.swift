import SwiftUI
import TaskManagerCore

struct GPUMemoryDetailView: View {
    @ObservedObject var store: MonitorStore
    let gpuID: String?
    let plotHeight: CGFloat
    let restore: () -> Void
    @ViewState private var showComparison = false

    private var latest: UnifiedMemoryComparison {
        let memory = store.snapshot.memory
        return UnifiedMemoryComparison(totalBytes: memory.totalBytes,
                                       systemUsedBytes: memory.usageAvailable ? memory.usedBytes : nil,
                                       gpuUsedBytes: store.snapshot.gpus.first { $0.id == gpuID }?.memoryInUseBytes)
    }

    var body: some View {
        let points = store.history.map { $0.memoryComparison(gpuID: gpuID) }
        let current = latest
        let gpuValues = points.map { $0.gpuUsedBytes.map { Double($0) } }
        let peak = points.flatMap { point in
            (showComparison ? [point.totalBytes, point.systemUsedBytes, point.gpuUsedBytes] : [point.gpuUsedBytes]).compactMap { $0 }
        }.max() ?? 0
        let currentPeak = (showComparison ? [current.totalBytes, current.systemUsedBytes, current.gpuUsedBytes] : [current.gpuUsedBytes]).compactMap { $0 }.max() ?? 0
        let maximum = max(1_048_576, Double(max(peak, currentPeak))) * 1.06
        let overlays: [ResourcePlotOverlay] = showComparison ? [
            .init(values: points.map { $0.totalBytes.map { Double($0) } }, color: .secondary, dash: [6, 4]),
            .init(values: points.map { $0.systemUsedBytes.map { Double($0) } }, color: .blue),
            .init(values: points.map { $0.cpuOtherEstimateBytes.map { Double($0) } }, color: .orange, dash: [2, 3])
        ] : []

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("GPU memory").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: restore) { Label("Restore", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .controlSize(.small).accessibilityLabel("Restore GPU overview")
            }
            Toggle("Overlay total, GPU and CPU memory", isOn: $showComparison)
                .toggleStyle(.switch).font(.system(size: 12))
                .accessibilityIdentifier("gpu-memory-overlay")

            VStack(spacing: 6) {
                HStack {
                    Text("Memory (\(maximum >= 1_073_741_824 ? "GB" : "MB"))")
                    Spacer()
                    Text(store.isPaused ? "Paused" : "Live")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(0..<6) { index in
                            if index > 0 { Spacer(minLength: 0) }
                            Text(axisValue(maximum * Double(5 - index) / 5, maximum: maximum))
                        }
                    }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary).frame(width: 32, height: plotHeight)
                    ResourcePlot(values: gpuValues, dates: store.history.map(\.timestamp), maximum: maximum, color: .purple, overlays: overlays)
                        .frame(height: plotHeight)
                        .overlay {
                            if !gpuValues.contains(where: { $0 != nil }) {
                                Text("GPU memory unavailable").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(showComparison ? "GPU and unified memory comparison history" : "GPU used memory history")
                        .accessibilityValue("GPU used \(MetricFormat.bytes(current.gpuUsedBytes))")
                }
                HStack {
                    Text("\(Int(max(60, (store.history.last?.timestamp ?? Date()).timeIntervalSince(store.history.first?.timestamp ?? Date())))) seconds")
                    Spacer()
                    Text("0")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 40)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 15) {
                if showComparison {
                    memoryMetric("Total memory", current.totalBytes, color: .secondary, dash: [6, 4], help: "Installed physical memory; a capacity reference, not memory usage.")
                    memoryMetric("System used", current.systemUsedBytes, color: .blue, help: "Overall system memory used, including apps, kernel and compressed memory.")
                }
                memoryMetric("GPU used", current.gpuUsedBytes, color: .purple, help: "This GPU's driver-reported in-use system memory, not allocated or reserved memory.")
                if showComparison {
                    memoryMetric("CPU / other (estimate)", current.cpuOtherEstimateBytes, color: .orange, dash: [2, 3], estimated: true,
                                 help: "System memory used minus this GPU's in-use counter. Shared allocations can overlap; this is not an exact CPU-only measurement.")
                }
            }
            Text(showComparison
                 ? "CPU / other is an estimate: system used minus this GPU’s in-use counter. Unified-memory allocations can overlap, so this is not an exact CPU-only measurement."
                 : "GPU used is the driver’s in-use memory counter. Enable the overlay to compare it with system usage and total physical memory.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func axisValue(_ value: Double, maximum: Double) -> String {
        String(format: "%.1f", value / (maximum >= 1_073_741_824 ? 1_073_741_824 : 1_048_576))
    }

    private func memoryMetric(_ title: String, _ bytes: UInt64?, color: Color, dash: [CGFloat] = [], estimated: Bool = false, help: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Path { path in path.move(to: CGPoint(x: 0, y: 4)); path.addLine(to: CGPoint(x: 18, y: 4)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash)).frame(width: 18, height: 8)
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text((estimated && bytes != nil ? "≈ " : "") + MetricFormat.bytes(bytes))
                .font(.system(size: 22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }.help(help).frame(maxWidth: .infinity, alignment: .leading)
    }
}
