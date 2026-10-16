import SwiftUI
import TaskManagerCore

private struct GraphTimeWindowKey: EnvironmentKey {
    static let defaultValue: GraphTimeWindow = .oneMinute
}
extension EnvironmentValues {
    var graphTimeWindow: GraphTimeWindow {
        get { self[GraphTimeWindowKey.self] }
        set { self[GraphTimeWindowKey.self] = newValue }
    }
}

struct PerformanceView: View {
    @ObservedObject var store: MonitorStore
    @ViewState private var isGPUMemoryExpanded = false
    private let hardware = HardwareInfo.read()
    private var selection: String { store.performanceSelection }
    private var dates: [Date] { store.history.map(\.timestamp) }
    private var disks: [DiskMetrics] { store.snapshot.disks }
    private var disk: DiskMetrics? { disks.first { "disk:" + $0.id == selection } }
    private var network: NetworkMetrics? { store.snapshot.networks.first { "network:" + $0.id == selection } }
    private var isGPU: Bool { selection == "gpu" || selection.hasPrefix("gpu:") }
    private var gpu: GPUMetrics? { store.snapshot.gpus.first { "gpu:" + $0.id == selection } ?? (selection == "gpu" ? store.snapshot.gpus.first : nil) }
    private var tint: Color { selection == "memory" ? .purple : disk != nil ? .green : network != nil ? .orange : isGPU ? .purple : .blue }

    var body: some View {
        let visibleIDs = Set(store.visiblePerformanceItems.map(\.id))
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    if visibleIDs.contains("cpu") { resourceRow("cpu", title: "CPU", value: MetricFormat.percent(store.snapshot.cpuUsage), color: .blue, values: store.history.map(\.cpu)) }
                    if visibleIDs.contains("memory") { resourceRow("memory", title: "Memory", value: memorySummary, color: .purple, values: store.history.map(\.memory)) }
                    ForEach(disks) { item in
                        if visibleIDs.contains("disk:" + item.id) { resourceRow("disk:" + item.id, title: item.name, value: diskSummary(item), color: .green, values: diskValues(item.id, write: false), scale: diskScale(item.id)) }
                    }
                    ForEach(store.snapshot.networks) { item in
                        if visibleIDs.contains("network:" + item.id) { resourceRow("network:" + item.id, title: item.name, value: "S: \(bits(item.sendBytesPerSecond)) R: \(bits(item.receiveBytesPerSecond))", color: .orange, values: networkValues(item.id, send: false), scale: networkScale(item.id)) }
                    }
                    if store.snapshot.gpus.isEmpty && visibleIDs.contains("gpu") {
                        resourceRow("gpu", title: "GPU 0", value: hardware.gpuName + " · —", color: .purple, values: [])
                    } else {
                        ForEach(Array(store.snapshot.gpus.enumerated()), id: \.element.id) { index, item in
                            if visibleIDs.contains("gpu:" + item.id) { resourceRow("gpu:" + item.id, title: "GPU \(index)", value: item.name + " · " + MetricFormat.percent(item.utilization), color: .purple, values: gpuValues(item.id, \.utilization)) }
                        }
                    }
                }.padding(.horizontal, 8).padding(.top, 10)
            }.frame(width: 206).background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            Divider()
            if visibleIDs.isEmpty {
                ContentUnavailableView { Label("All performance items are hidden", systemImage: "eye.slash") } description: {
                    Text("Show items from the More menu or Settings.")
                } actions: { Button("Show all performance items") { store.showAllPerformanceItems() } }
            } else {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title).font(.system(size: 28, weight: .regular))
                            Spacer(minLength: 12)
                            Text(subtitle).font(.system(size: 13)).lineLimit(1)
                        }.padding(.bottom, 3)
                        if selection == "memory" { memoryContent(height: max(160, graphHeight(geometry.size.height) - 65), width: geometry.size.width - 52) }
                        else if let disk { diskContent(disk, height: graphHeight(geometry.size.height)) }
                        else if let network { networkContent(network, height: graphHeight(geometry.size.height)) }
                        else if isGPU {
                            if isGPUMemoryExpanded {
                                GPUMemoryDetailView(store: store, gpuID: gpu?.id, plotHeight: max(180, min(460, geometry.size.height - 335))) {
                                    isGPUMemoryExpanded = false
                                }
                            } else {
                                gpuContent(height: max(180, min(240, geometry.size.height - 420)))
                            }
                        }
                        else { cpuContent(height: graphHeight(geometry.size.height), width: geometry.size.width - 52) }
                    }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 22)
                }
            }.id(selection)
            }
        }.onChange(of: selection) { isGPUMemoryExpanded = false }
        .environment(\.graphTimeWindow, store.graphWindow)
    }
    private var title: String {
        if selection == "memory" { return "Memory" }
        if let disk { return disk.name + (disk.bsdName.map { " (" + $0 + ")" } ?? "") }
        if let network { return network.name }
        if isGPU { return "GPU \(store.snapshot.gpus.firstIndex { $0.id == gpu?.id } ?? 0)" }
        return "CPU"
    }
    private var subtitle: String {
        if selection == "memory" { return MetricFormat.bytes(store.snapshot.memory.totalBytes) }
        if let disk { return disk.model ?? disk.primaryVolume?.name ?? disk.name }
        if let network { return network.id }
        return isGPU ? (gpu?.name ?? hardware.gpuName) : hardware.cpuName
    }
    private var memorySummary: String {
        let m = store.snapshot.memory
        return "\(MetricFormat.bytes(m.usageAvailable ? m.usedBytes : nil))/\(MetricFormat.bytes(m.totalBytes)) (\(MetricFormat.percent(m.usedPercent)))"
    }
    private func temperature(_ celsius: Double?) -> String { celsius.map { String(format: "%.1f °C", $0) } ?? "—" }
    private func temperatureColor(_ band: TemperatureBand?) -> Color {
        switch band {
        case .safe: return .green
        case .warm: return .yellow
        case .hot: return .red
        case .throttlingRisk, .thermalThrottling: return .purple
        case nil: return .secondary
        }
    }
    private func temperatureOverlay(_ value: Double?, label: String = "Temp · avg") -> some View {
        let band = TemperatureBand.classify(value, pressure: store.snapshot.temperatures.thermalPressure)
        return Text(label + " " + temperature(value) + (band.map { " · " + $0.label } ?? ""))
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(temperatureColor(band))
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
            .padding(5).padding(.trailing, 44).allowsHitTesting(false)
            .help(store.snapshot.temperatures.note)
    }
    private func temperatureHistory(_ series: TemperatureSeries) -> [ResourcePlotOverlay] {
        guard store.showTemperatureGraph else { return [] }
        return [ResourcePlotOverlay(values: store.history.map { series.value(in: $0) }, color: .green, dash: [5, 3], maximum: TemperatureScale.maximum, minimum: TemperatureScale.minimum, sampleColors: store.history.map { temperatureColor(TemperatureBand.classify(series.value(in: $0), pressure: $0.temperatures.thermalPressure)) })]
    }
    private func frequency(_ mhz: Double?) -> String { mhz.map { String(format: "%.2f GHz", $0 / 1000) } ?? "—" }
    private func diskSummary(_ disk: DiskMetrics) -> String {
        if let volume = disk.primaryVolume {
            return "\(volume.name) · \(MetricFormat.percent(volume.usedPercent)) used"
        }
        return "\(disk.bsdName ?? "") · \(MetricFormat.rate(sum(disk.readBytesPerSecond, disk.writeBytesPerSecond)))"
    }
    private func graphHeight(_ available: CGFloat) -> CGFloat { max(190, min(340, available - 265)) }
    private func resourceRow(_ id: String, title: String, value: String, color: Color, values: [Double?], scale: Double = 100) -> some View {
        Button { store.performanceSelection = id } label: {
            HStack(spacing: 11) {
                ResourcePlot(values: values, dates: dates, maximum: scale, color: color, compact: true).frame(width: 60, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12)).lineLimit(1)
                    Text(value).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).monospacedDigit()
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: 64)
                .background(selection == id ? Color.primary.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: store.appearance == .macOS ? 8 : 0))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .overlay(StableContextMenu {
            [
                .action("Hide \(title)") {
                    if let item = store.performanceItems.first(where: { $0.id == id }) { store.setPerformanceItem(item, shown: false) }
                },
                .action("Show all performance items") { store.showAllPerformanceItems() }
            ]
        })
    }
    @ViewBuilder private func cpuContent(height: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 5) {
            if store.cpuGraphLogical {
                Text("P · Performance cores    E · Efficiency cores").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let count = max(1, hardware.logicalCPUs)
                let columns = count > 16 ? 6 : count > 8 ? 5 : count > 4 ? 4 : 2
                let rows = (count + columns - 1) / columns
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(0..<count, id: \.self) { index in
                        ResourcePlot(values: store.history.map { $0.logicalCPU.indices.contains(index) ? $0.logicalCPU[index] : nil }, dates: dates, secondValues: store.showKernelTimes ? store.history.map { $0.logicalKernel.indices.contains(index) ? $0.logicalKernel[index] : nil } : [], color: .blue, logical: true, logicalTitle: "CPU \(index + 1) · \(hardware.logicalCoreKinds[index]?.rawValue ?? "?")", currentUsage: store.snapshot.logicalCPUUsage.indices.contains(index) ? store.snapshot.logicalCPUUsage[index] : nil)
                        .frame(height: (height - CGFloat(rows - 1) * 8) / CGFloat(rows))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Logical processor \(index + 1), \(hardware.logicalCoreKinds[index]?.name ?? "Unknown type") core, \(MetricFormat.percent(store.snapshot.logicalCPUUsage.indices.contains(index) ? store.snapshot.logicalCPUUsage[index] : nil))")
                        .help("Logical processor \(index + 1) · \(hardware.logicalCoreKinds[index]?.name ?? "Unknown type") core · 0–100% utilization")
                    }
                }
            } else {
                axis("% Utilization", maximum: "100%")
                ResourcePlot(values: store.history.map(\.cpu), dates: dates, secondValues: store.showKernelTimes ? store.history.map(\.kernelCPU) : [], color: .blue, overlays: temperatureHistory(.cpuAverage), temperatureAxis: store.showTemperatureGraph).frame(height: height)
                    .overlay(alignment: .topTrailing) {
                        if store.showTemperatureGraph { temperatureOverlay(store.snapshot.temperatures.cpuAverageCelsius, label: "Temp · avg") }
                    }
            }
            timeAxis
        }.overlay(StableContextMenu {
            [
                .submenu("Change graph to", [
                    .action("Overall utilization", checked: !store.cpuGraphLogical) { store.cpuGraphLogical = false },
                    .action("Logical processors", checked: store.cpuGraphLogical) { store.cpuGraphLogical = true }
                ]),
                .action("Show kernel times", checked: store.showKernelTimes) { store.showKernelTimes.toggle() }
            ] + (store.cpuGraphLogical ? [] : [
                .action("Show temperature graph", checked: store.showTemperatureGraph) { store.showTemperatureGraph.toggle() }
            ])
        })
        let layout = width < 540 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 30))
        layout {
            VStack(alignment: .leading, spacing: 15) {
                let metricsLayout = width < 700 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 15)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                metricsLayout {
                    HStack(spacing: 24) {
                        metric("Utilization", MetricFormat.percent(store.snapshot.cpuUsage))
                        metric("Temp · avg", temperature(store.snapshot.temperatures.cpuAverageCelsius), size: 21, help: store.snapshot.temperatures.note)
                    }
                    HStack(spacing: 24) {
                        metric("Speed · P cores", frequency(store.snapshot.cpuFrequency.performanceMHz), size: 21, help: store.snapshot.cpuFrequency.note)
                        metric("Speed · E cores", frequency(store.snapshot.cpuFrequency.efficiencyMHz), size: 21, help: store.snapshot.cpuFrequency.note)
                    }
                }
                HStack(spacing: 22) {
                    metric("Processes", String(store.snapshot.processes.count), size: 18)
                    metric("Threads", String(store.snapshot.processes.compactMap(\.threadCount).reduce(0, +)), size: 18)
                    metric("Handles", "—", size: 18, help: "Windows handle counts have no equivalent public aggregate counter on macOS.")
                }
                metric("Up time", MetricFormat.uptime(store.snapshot.uptime), size: 21)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                pair("Base speed:", hardware.baseFrequencyHz.map { String(format: "%.2f GHz", Double($0) / 1e9) } ?? "—")
                pair("Sockets:", hardware.sockets.map(String.init) ?? "—")
                pair("Cores:", String(hardware.physicalCPUs))
                pair("Logical processors:", String(hardware.logicalCPUs))
                pair("Virtualization:", hardware.virtualizationSupported.map { $0 ? "Supported" : "Unavailable" } ?? "—")
                pair("L1 cache:", MetricFormat.bytes(hardware.l1DataBytes))
                pair("L2 cache:", MetricFormat.bytes(hardware.l2Bytes))
                pair("L3 cache:", MetricFormat.bytes(hardware.l3Bytes))
            }.frame(minWidth: 200)
        }.padding(.top, 4)
        note("CPU temperature averages readable die sensors. Sensors refresh at most every two seconds.")
        note("Experimental CPU frequency · Active-time averages for performance and efficiency clusters; idle time is excluded.")
    }
    @ViewBuilder private func memoryContent(height: CGFloat, width: CGFloat) -> some View {
        let m = store.snapshot.memory
        graph("Memory usage", maximumLabel: MetricFormat.bytes(m.totalBytes), values: store.history.map { $0.memory.map { $0 * Double(m.totalBytes) / 100 } }, maximum: Double(m.totalBytes), height: max(160, height - 85))
        MemoryPressurePlot(history: store.history, current: m.pressureLevel)
            .frame(height: 105)
        timeAxis
        Text("Memory composition").font(.system(size: 11)).foregroundStyle(.secondary)
        GeometryReader { g in
            HStack(spacing: 0) {
                Rectangle().fill(Color.purple.opacity(0.25)).frame(width: m.usageAvailable ? g.size.width * min(1, Double(m.usedBytes) / max(1, Double(m.totalBytes))) : 0)
                Rectangle().fill(Color.purple.opacity(0.035))
            }.overlay(Rectangle().stroke(Color.purple.opacity(0.4), lineWidth: 1))
        }.frame(height: 34).help("In use and available physical memory. File-backed cache remains reclaimable.")
        let layout = width < 580 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 26))
        layout {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 24) { metric("In use (Compressed)", "\(MetricFormat.bytes(m.usageAvailable ? m.usedBytes : nil)) (\(MetricFormat.bytes(m.usageAvailable ? m.compressedBytes : nil)))", size: 19); metric("Available", MetricFormat.bytes(m.usageAvailable ? m.availableBytes : nil), size: 19) }
                HStack(spacing: 24) { metric("Swap used", MetricFormat.bytes(m.swapAvailable ? m.swapUsedBytes : nil), size: 18); metric("Cached", MetricFormat.bytes(m.cachedBytes), size: 18) }
                HStack(spacing: 24) { metric("Wired", MetricFormat.bytes(m.usageAvailable ? m.wiredBytes : nil), size: 18); metric("Free", MetricFormat.bytes(m.freeBytes), size: 18) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) { pair("Memory pressure:", m.pressure); pair("Form factor:", "Unified memory"); pair("Hardware reserved:", "—") }.frame(minWidth: 170)
        }
    }
    @ViewBuilder private func diskContent(_ d: DiskMetrics, height: CGFloat) -> some View {
        ForEach(d.volumes) { volume in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(volume.name + " · Capacity used").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(MetricFormat.bytes(volume.usedBytes)) / \(MetricFormat.bytes(volume.totalBytes)) (\(MetricFormat.percent(volume.usedPercent)))")
                        .font(.system(size: 11)).monospacedDigit()
                }
                GeometryReader { geometry in
                    Rectangle().fill(Color.green.opacity(0.07))
                        .overlay(alignment: .leading) { Rectangle().fill(Color.green.opacity(0.65)).frame(width: geometry.size.width * (volume.usedPercent ?? 0) / 100) }
                        .overlay { Rectangle().strokeBorder(Color.green.opacity(0.5), lineWidth: 1) }
                }.frame(height: 12)
                Text("Available: \(MetricFormat.bytes(volume.freeBytes)) · \(volume.mountPath)").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.top, 5)
        }
        graph("Active time", maximumLabel: "100%", values: [], height: height * 0.8, unavailableText: "Active time unavailable\nNo validated disk busy-time counter")
            .help("Percentage of time this drive is busy handling I/O, not storage capacity used. Request timings may overlap and cannot establish this percentage.")
        graph("Disk transfer rate", maximumLabel: MetricFormat.rate(diskScale(d.id)), values: diskValues(d.id, write: false), second: diskValues(d.id, write: true), maximum: diskScale(d.id), height: height * 0.2)
        HStack(alignment: .top, spacing: 35) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 28) { metric("Active time", "—"); metric("Average response time", d.averageResponseMilliseconds.map { String(format: "%.2f ms", $0) } ?? "—", help: "Mean duration of completed I/O requests from this device’s driver counters; unavailable when no I/O completes.") }
                HStack(spacing: 28) { metric("Read speed", MetricFormat.rate(d.readBytesPerSecond), size: 20); metric("Write speed", MetricFormat.rate(d.writeBytesPerSecond), size: 20) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                pair(d.kind == .volume ? "Volume capacity:" : "Drive capacity:", d.totalBytes > 0 ? MetricFormat.bytes(d.totalBytes) : "—")
                pair("Device:", d.bsdName ?? "—")
                pair("Type:", d.kind == .image ? "Disk image · virtual" : d.kind == .volume ? "Mounted volume" : "Physical drive")
                if let connection = d.connection { pair("Connection:", connection) }
                pair("System disk:", d.volumes.contains(where: { $0.mountPath == "/" }) ? "Yes" : "No")
            }
        }
        if d.volumes.isEmpty { note("No mounted user volume is associated with this device; used space is unavailable.") }
        note(d.kind == .volume ? "Mounted filesystem capacity. Device throughput could not be associated with this volume." : "Read/write rates cover this whole device. Capacity used is filesystem space unavailable to ordinary writes; APFS volumes can share container space and are not added together.")
        note("Solid line: read. Dashed line: write. Active time is the percentage of time the drive is busy, separate from capacity used. No validated busy-time reading is available on this Mac.")
    }
    @ViewBuilder private func networkContent(_ n: NetworkMetrics, height: CGFloat) -> some View {
        graph("Throughput", maximumLabel: bits(networkScale(n.id)), values: networkValues(n.id, send: false), second: networkValues(n.id, send: true), maximum: networkScale(n.id), height: height)
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 16) { metric("Send", bits(n.sendBytesPerSecond)); metric("Receive", bits(n.receiveBytesPerSecond)) }
            VStack(alignment: .leading, spacing: 7) { pair("Adapter name:", n.id); pair("Connection type:", n.name); pair("IP address:", n.address ?? "—") }.padding(.top, 3)
            Spacer(minLength: 0)
        }
        note("Solid line: receive. Dashed line: send. Rates are read from local interface counters.")
    }
    @ViewBuilder private func gpuContent(height: CGFloat) -> some View {
        let id = gpu?.id ?? ""
        let peakMemory = store.history.compactMap { $0.gpuByID[id] }.flatMap { [$0.memoryInUseBytes, $0.memoryAllocatedBytes].compactMap { $0 } }.max() ?? 0
        let memoryScale = max(1, store.snapshot.memory.totalBytes, peakMemory)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(0..<store.gpuChartLayout.metrics.count, id: \.self) { slot in
                gpuChart(slot: slot, id: id, memoryScale: memoryScale, height: height / 2 - 22)
            }
        }
        VStack(spacing: 5) {
            HStack {
                Text("GPU memory in use").foregroundStyle(.secondary)
                Button { isGPUMemoryExpanded = true } label: { Label("Enlarge", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .controlSize(.mini).accessibilityLabel("Enlarge GPU memory")
                    .help("Enlarge the graph and compare GPU, CPU and total memory")
                Spacer()
                Text(MetricFormat.bytes(memoryScale)).foregroundStyle(.secondary)
            }.font(.system(size: 11))
            ResourcePlot(values: gpuMemoryValues(id, allocated: false), dates: dates, maximum: Double(memoryScale), color: tint)
                .frame(height: 35).contentShape(Rectangle())
                .onTapGesture(count: 2) { isGPUMemoryExpanded = true }
            timeAxis
        }
        graph("GPU memory allocated", maximumLabel: MetricFormat.bytes(memoryScale), values: gpuMemoryValues(id, allocated: true), maximum: Double(memoryScale), height: 35)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 15) {
            metric("Utilization", MetricFormat.percent(gpu?.utilization))
            metric("Temp · avg", temperature(store.snapshot.temperatures.gpuID == id ? store.snapshot.temperatures.gpuAverageCelsius : nil), size: 21, help: store.snapshot.temperatures.note)
            metric("GPU memory in use", MetricFormat.bytes(gpu?.memoryInUseBytes), size: 21)
            metric("GPU memory allocated", MetricFormat.bytes(gpu?.memoryAllocatedBytes), size: 21)
        }
        HStack(spacing: 25) {
            pair("GPU cores:", gpu?.coreCount.map(String.init) ?? "—")
            pair("System unified memory:", MetricFormat.bytes(store.snapshot.memory.totalBytes))
        }
        note(gpu?.utilization == nil && gpu?.rendererUtilization == nil && gpu?.tilerUtilization == nil
             ? "GPU counters are unavailable from this Mac's driver."
             : "Choose a metric above each chart; choices are saved. GPU, renderer, tiler and memory readings come from the driver. Video Decode, Video Encode and Copy percentages have no validated reading on this Mac. Allocated memory may include reusable allocations.")
    }
    private func gpuChart(slot: Int, id: String, memoryScale: UInt64, height: CGFloat) -> some View {
        let metric = store.gpuChartLayout.metrics[slot]
        let values = store.history.map { metric.value(in: $0.gpuByID[id]) }
        let showsTemperature = store.showTemperatureGraph && metric == .utilization
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                GPUChartMetricMenu(slot: slot, selected: metric, gpu: gpu) { store.setGPUChartMetric($0, at: slot) }
                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 18)
                Text(metric.isMemory ? MetricFormat.bytes(memoryScale) : "100%")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
            }
            ResourcePlot(values: values, dates: dates, maximum: metric.isMemory ? Double(memoryScale) : 100, color: tint, overlays: showsTemperature ? temperatureHistory(.gpu(id)) : [], temperatureAxis: showsTemperature)
                .frame(height: height)
                .overlay {
                    if !values.contains(where: { $0 != nil }) {
                        Text("Unavailable").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showsTemperature {
                        temperatureOverlay(store.snapshot.temperatures.gpuID == id ? store.snapshot.temperatures.gpuAverageCelsius : nil)
                    }
                }
                .help(metric.value(in: gpu) == nil ? metric.unavailableReason : metric.title)
                .accessibilityLabel("GPU chart \(slot + 1): \(metric.title)")
            timeAxis
        }
    }
    private func gpuValues(_ id: String, _ keyPath: KeyPath<GPUMetrics, Double?>) -> [Double?] {
        store.history.map { $0.gpuByID[id]?[keyPath: keyPath] }
    }
    private func gpuMemoryValues(_ id: String, allocated: Bool) -> [Double?] {
        store.history.map { point in
            let value = allocated ? point.gpuByID[id]?.memoryAllocatedBytes : point.gpuByID[id]?.memoryInUseBytes
            return value.map { Double($0) }
        }
    }
    private func graph(_ label: String, maximumLabel: String, values: [Double?], second: [Double?] = [], maximum: Double = 100, height: CGFloat, unavailableText: String? = nil) -> some View {
        VStack(spacing: 5) { axis(label, maximum: maximumLabel); ResourcePlot(values: values, dates: dates, secondValues: second, maximum: maximum, color: tint).frame(height: height).overlay { if !values.contains(where: { $0 != nil }) { Text(unavailableText ?? "—").font(.system(size: unavailableText == nil ? 16 : 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(12) } }; timeAxis }
    }
    private func axis(_ label: String, maximum: String) -> some View { HStack { Text(label); Spacer(); Text(maximum) }.font(.system(size: 11)).foregroundStyle(.secondary) }
    private var timeAxis: some View {
        return HStack { Text(store.graphWindow.axisLabel); Spacer(); Text("Latest sample") }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .help("Time runs from older samples on the left to the latest recorded sample on the right. The fixed window is shared by all graphs and configurable in Settings. Pausing freezes the latest recorded sample.")
    }
    private func metric(_ title: String, _ value: String, size: CGFloat = 24, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 11)).foregroundStyle(.secondary); Text(value).font(.system(size: size, weight: .regular)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8) }.help(help)
    }
    private func pair(_ title: String, _ value: String) -> some View { HStack(alignment: .firstTextBaseline, spacing: 9) { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }.font(.system(size: 11)) }
    private func note(_ text: String) -> some View { Text(text).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4) }
    private func sum(_ a: Double?, _ b: Double?) -> Double? { a == nil && b == nil ? nil : (a ?? 0) + (b ?? 0) }
    private func diskValues(_ id: String, write: Bool) -> [Double?] { store.history.map { write ? $0.diskByID[id]?.writeBytesPerSecond : $0.diskByID[id]?.readBytesPerSecond } }
    private func diskScale(_ id: String) -> Double { max(1024, (diskValues(id, write: false) + diskValues(id, write: true)).compactMap { $0 }.max() ?? 1024) * 1.1 }
    private func networkValues(_ id: String, send: Bool) -> [Double?] { store.history.map { send ? $0.networkByID[id]?.sendBytesPerSecond : $0.networkByID[id]?.receiveBytesPerSecond } }
    private func networkScale(_ id: String) -> Double { max(128, (networkValues(id, send: false) + networkValues(id, send: true)).compactMap { $0 }.max() ?? 128) * 1.1 }
    private func bits(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        let value = rate * 8
        if value >= 1e9 { return String(format: "%.1f Gbps", value / 1e9) }
        if value >= 1e6 { return String(format: "%.1f Mbps", value / 1e6) }
        return String(format: "%.1f Kbps", value / 1e3)
    }
}

struct ResourcePlotOverlay {
    var values: [Double?]
    var color: Color
    var dash: [CGFloat] = []
    var maximum: Double? = nil
    var minimum: Double = 0
    var sampleColors: [Color] = []
}

struct ResourcePlot: View {
    let values: [Double?]
    var dates: [Date] = []
    var secondValues: [Double?] = []
    var maximum: Double = 100
    var color: Color = .blue
    var compact = false
    var logical = false
    var logicalTitle: String? = nil
    var currentUsage: Double? = nil
    var overlays: [ResourcePlotOverlay] = []
    var temperatureAxis = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.graphTimeWindow) private var graphWindow
    var body: some View {
        Canvas { context, canvasSize in
            var size = canvasSize
            if let logicalTitle {
                let title = Text(logicalTitle).font(.system(size: 10)).foregroundColor(.secondary)
                let usage = Text(MetricFormat.percent(currentUsage)).font(.system(size: 10)).monospacedDigit().foregroundColor(.secondary)
                context.draw(title, at: .zero, anchor: .topLeading)
                context.draw(usage, at: CGPoint(x: size.width, y: 0), anchor: .topTrailing)
                context.translateBy(x: 0, y: 16)
                size.height = max(1, size.height - 16)
            }
            if temperatureAxis {
                size.width = max(1, size.width - 44)
                for tick in TemperatureScale.ticks {
                    let y = size.height * (1 - (TemperatureScale.position(tick) ?? 0))
                    var mark = Path(); mark.move(to: CGPoint(x: size.width, y: y)); mark.addLine(to: CGPoint(x: size.width + 5, y: y))
                    context.stroke(mark, with: .color(.secondary), lineWidth: 0.5)
                    let label = Text("\(Int(tick)) °C").font(.system(size: 9)).monospacedDigit().foregroundColor(.secondary)
                    context.draw(label, at: CGPoint(x: size.width + 8, y: y), anchor: tick == TemperatureScale.minimum ? .bottomLeading : tick == TemperatureScale.maximum ? .topLeading : .leading)
                }
            }
            // Stroke entirely inside the canvas: an edge-centered stroke is clipped.
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(rect), with: .color(color.opacity(0.035)))
            var grid = Path()
            for i in 1..<10 { let x = rect.minX + rect.width * Double(i) / 10; grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY)) }
            let divisions = temperatureAxis ? 4 : 5
            for i in 1..<divisions { let y = rect.minY + rect.height * Double(i) / Double(divisions); grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y)) }
            context.stroke(grid, with: .color(color.opacity(compact ? 0.12 : scheme == .dark ? 0.24 : 0.18)), lineWidth: 0.5)
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            draw(values, size: size, context: &context, dashed: false)
            if !secondValues.isEmpty { draw(secondValues, size: size, context: &context, dashed: true) }
            for overlay in overlays {
                draw(overlay.values, size: size, context: &context, dashed: true, lineColor: overlay.color, lineDash: overlay.dash, scaleMaximum: overlay.maximum, scaleMinimum: overlay.minimum, sampleColors: overlay.sampleColors)
            }
            context.stroke(Path(rect), with: .color(color.opacity(scheme == .dark ? 0.7 : 0.5)), lineWidth: 1)
        }
    }
    private func draw(_ values: [Double?], size: CGSize, context: inout GraphicsContext, dashed: Bool, lineColor: Color? = nil, lineDash: [CGFloat]? = nil, scaleMaximum: Double? = nil, scaleMinimum: Double = 0, sampleColors: [Color] = []) {
        guard values.count > 1 else { return }
        let capacity = max(values.count, compact ? 30 : 60)
        let timed = dates.count == values.count
        let timeline = GraphTimeline(end: dates.last ?? Date(timeIntervalSince1970: 0), window: graphWindow)
        var segments: [(points: [CGPoint], color: Color?)] = []
        var segment: [CGPoint] = []
        var segmentColor: Color? = nil
        for (index, value) in values.enumerated() {
            let gap = timed && index > 0 && dates[index].timeIntervalSince(dates[index - 1]) > 6
            if gap || value == nil || value?.isFinite == false {
                if !segment.isEmpty { segments.append((segment, segmentColor)); segment.removeAll(keepingCapacity: true) }
            }
            guard let value, value.isFinite else { continue }
            let fraction = timed ? timeline.position(dates[index]) : Double(capacity - values.count + index) / Double(capacity - 1)
            guard let fraction else { continue }
            let x = size.width * fraction
            // Keep independent-axis overlay strokes visible at both bounds.
            let inset = scaleMaximum == nil ? 0 : min(1.5, size.height / 2)
            let y = inset + (size.height - 2 * inset) * (1 - min(1, max(0, (value - scaleMinimum) / max(1, (scaleMaximum ?? maximum) - scaleMinimum))))
            let sampleColor = sampleColors.indices.contains(index) ? sampleColors[index] : lineColor
            if !segment.isEmpty, sampleColor != segmentColor, let previous = segment.last {
                segments.append((segment, segmentColor)); segment = [previous]
            }
            segmentColor = sampleColor
            segment.append(CGPoint(x: x, y: y))
        }
        if !segment.isEmpty { segments.append((segment, segmentColor)) }
        for segment in segments {
            let points = segment.points
            guard points.count > 1, let first = points.first, let last = points.last else { continue }
            var line = Path(); line.move(to: first)
            points.dropFirst().forEach { line.addLine(to: $0) }
            if !dashed {
                var fill = line; fill.addLine(to: CGPoint(x: last.x, y: size.height)); fill.addLine(to: CGPoint(x: first.x, y: size.height)); fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0.025)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color((segment.color ?? color).opacity(segment.color != nil ? 0.95 : dashed ? 0.55 : 0.9)), style: StrokeStyle(lineWidth: compact ? 1 : logical ? 1.2 : 1.6, lineJoin: .round, dash: lineDash ?? (dashed ? [4, 3] : [])))
        }
    }
}
