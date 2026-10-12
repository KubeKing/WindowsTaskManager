import SwiftUI
import TaskManagerCore

struct PerformanceView: View {
    @ObservedObject var store: MonitorStore
    @ViewState private var isGPUMemoryExpanded = false
    private let hardware = HardwareInfo.read()
    private var selection: String { store.performanceSelection }
    private var dates: [Date] { store.history.map(\.timestamp) }
    private var disks: [DiskMetrics] {
        store.snapshot.disks.sorted { ($0.totalBytes == 0 ? 0 : 1, $0.id) < ($1.totalBytes == 0 ? 0 : 1, $1.id) }
    }
    private var disk: DiskMetrics? { disks.first { "disk:" + $0.id == selection } }
    private var network: NetworkMetrics? { store.snapshot.networks.first { "network:" + $0.id == selection } }
    private var isGPU: Bool { selection == "gpu" || selection.hasPrefix("gpu:") }
    private var gpu: GPUMetrics? { store.snapshot.gpus.first { "gpu:" + $0.id == selection } ?? (selection == "gpu" ? store.snapshot.gpus.first : nil) }
    private var tint: Color { selection == "memory" ? .purple : disk != nil ? .green : network != nil ? .orange : isGPU ? .purple : .blue }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    resourceRow("cpu", title: "CPU", value: MetricFormat.percent(store.snapshot.cpuUsage), color: .blue, values: store.history.map(\.cpu))
                    resourceRow("memory", title: "Memory", value: memorySummary, color: .purple, values: store.history.map(\.memory))
                    ForEach(Array(disks.enumerated()), id: \.element.id) { index, item in
                        resourceRow("disk:" + item.id, title: item.totalBytes > 0 ? item.name : "Disk \(index)", value: item.totalBytes > 0 ? "\(MetricFormat.bytes(item.freeBytes)) free" : MetricFormat.rate(sum(item.readBytesPerSecond, item.writeBytesPerSecond)), color: .green, values: diskValues(item.id, write: false), scale: diskScale(item.id))
                    }
                    ForEach(store.snapshot.networks) { item in
                        resourceRow("network:" + item.id, title: item.name, value: "S: \(bits(item.sendBytesPerSecond)) R: \(bits(item.receiveBytesPerSecond))", color: .orange, values: networkValues(item.id, send: false), scale: networkScale(item.id))
                    }
                    if store.snapshot.gpus.isEmpty {
                        resourceRow("gpu", title: "GPU 0", value: hardware.gpuName + " · —", color: .purple, values: [])
                    } else {
                        ForEach(Array(store.snapshot.gpus.enumerated()), id: \.element.id) { index, item in
                            resourceRow("gpu:" + item.id, title: "GPU \(index)", value: item.name + " · " + MetricFormat.percent(item.utilization), color: .purple, values: gpuValues(item.id, \.utilization))
                        }
                    }
                }.padding(.horizontal, 8).padding(.top, 10)
            }.frame(width: 206).background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            Divider()
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
            }
        }.onChange(of: selection) { isGPUMemoryExpanded = false }
    }
    private var title: String {
        if selection == "memory" { return "Memory" }
        if let disk, let index = disks.firstIndex(where: { $0.id == disk.id }) { return disk.totalBytes > 0 ? disk.name : "Disk \(index)" }
        if let network { return network.name }
        if isGPU { return "GPU \(store.snapshot.gpus.firstIndex { $0.id == gpu?.id } ?? 0)" }
        return "CPU"
    }
    private var subtitle: String {
        if selection == "memory" { return MetricFormat.bytes(store.snapshot.memory.totalBytes) }
        if let disk { return disk.name }
        if let network { return network.id }
        return isGPU ? (gpu?.name ?? hardware.gpuName) : hardware.cpuName
    }
    private var memorySummary: String {
        let m = store.snapshot.memory
        return "\(MetricFormat.bytes(m.usageAvailable ? m.usedBytes : nil))/\(MetricFormat.bytes(m.totalBytes)) (\(MetricFormat.percent(m.usedPercent)))"
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
    }
    @ViewBuilder private func cpuContent(height: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 5) {
            axis("% Utilization", maximum: "100%")
            if store.cpuGraphLogical {
                let count = max(1, hardware.logicalCPUs)
                let columns = count > 16 ? 6 : count > 8 ? 5 : count > 4 ? 4 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
                    ForEach(0..<count, id: \.self) { index in
                        ResourcePlot(values: store.history.map { $0.logicalCPU.indices.contains(index) ? $0.logicalCPU[index] : nil }, dates: dates, secondValues: store.showKernelTimes ? store.history.map { $0.logicalKernel.indices.contains(index) ? $0.logicalKernel[index] : nil } : [], color: .blue)
                            .frame(height: (height - CGFloat((count + columns - 1) / columns - 1) * 5) / CGFloat((count + columns - 1) / columns))
                            .help("Logical processor \(index + 1)")
                    }
                }
            } else {
                ResourcePlot(values: store.history.map(\.cpu), dates: dates, secondValues: store.showKernelTimes ? store.history.map(\.kernelCPU) : [], color: .blue).frame(height: height)
            }
            timeAxis
        }.contextMenu {
            Menu("Change graph to") {
                Button { store.cpuGraphLogical = false } label: { Label("Overall utilization", systemImage: store.cpuGraphLogical ? "circle" : "checkmark") }
                Button { store.cpuGraphLogical = true } label: { Label("Logical processors", systemImage: store.cpuGraphLogical ? "checkmark" : "circle") }
            }
            Toggle("Show kernel times", isOn: $store.showKernelTimes)
        }
        let layout = width < 540 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 30))
        layout {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 34) { metric("Utilization", MetricFormat.percent(store.snapshot.cpuUsage)); metric("Speed", "—", help: "Live processor frequency is not available through public macOS counters.") }
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
    }
    @ViewBuilder private func memoryContent(height: CGFloat, width: CGFloat) -> some View {
        let m = store.snapshot.memory
        graph("Memory usage", maximumLabel: MetricFormat.bytes(m.totalBytes), values: store.history.map { $0.memory.map { $0 * Double(m.totalBytes) / 100 } }, maximum: Double(m.totalBytes), height: height)
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
        graph("Active time", maximumLabel: "100%", values: [], height: height * 0.8)
            .help("Device active time is not exposed by supported public macOS counters.")
        graph("Disk transfer rate", maximumLabel: MetricFormat.rate(diskScale(d.id)), values: diskValues(d.id, write: false), second: diskValues(d.id, write: true), maximum: diskScale(d.id), height: height * 0.2)
        HStack(alignment: .top, spacing: 35) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 28) { metric("Active time", "—"); metric("Average response time", "—") }
                HStack(spacing: 28) { metric("Read speed", MetricFormat.rate(d.readBytesPerSecond), size: 20); metric("Write speed", MetricFormat.rate(d.writeBytesPerSecond), size: 20) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                pair("Capacity:", d.totalBytes > 0 ? MetricFormat.bytes(d.totalBytes) : "—")
                pair("Available:", d.totalBytes > 0 ? MetricFormat.bytes(d.freeBytes) : "—")
                pair("Device:", d.id)
                pair("Type:", d.totalBytes > 0 ? "Mounted volume" : "Physical device")
            }
        }
        note("Solid line: read. Dashed line: write. Active time and response time are unavailable on macOS.")
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            graph("GPU utilization", maximumLabel: "100%", values: gpuValues(id, \.utilization), height: height / 2 - 22)
            graph("Renderer", maximumLabel: "100%", values: gpuValues(id, \.rendererUtilization), height: height / 2 - 22)
            graph("Tiler", maximumLabel: "100%", values: gpuValues(id, \.tilerUtilization), height: height / 2 - 22)
            graph("Video Decode", maximumLabel: "—", values: [], height: height / 2 - 22)
                .help("The driver does not expose a separate Video Decode utilization counter.")
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
        HStack(alignment: .top, spacing: 30) {
            metric("Utilization", MetricFormat.percent(gpu?.utilization))
            metric("GPU memory in use", MetricFormat.bytes(gpu?.memoryInUseBytes), size: 21)
            metric("GPU memory allocated", MetricFormat.bytes(gpu?.memoryAllocatedBytes), size: 21)
        }
        HStack(spacing: 25) {
            pair("GPU cores:", gpu?.coreCount.map(String.init) ?? "—")
            pair("System unified memory:", MetricFormat.bytes(store.snapshot.memory.totalBytes))
        }
        note(gpu?.utilization == nil && gpu?.rendererUtilization == nil && gpu?.tilerUtilization == nil
             ? "GPU counters are unavailable from this Mac's driver."
             : "Live driver-reported GPU, renderer and tiler activity. Apple silicon shares system memory; allocated memory can include reusable allocations. Separate Copy and Video engine counters are unavailable.")
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
    private func graph(_ label: String, maximumLabel: String, values: [Double?], second: [Double?] = [], maximum: Double = 100, height: CGFloat) -> some View {
        VStack(spacing: 5) { axis(label, maximum: maximumLabel); ResourcePlot(values: values, dates: dates, secondValues: second, maximum: maximum, color: tint).frame(height: height).overlay { if !values.contains(where: { $0 != nil }) { Text("—").font(.system(size: 16)).foregroundStyle(.secondary) } }; timeAxis }
    }
    private func axis(_ label: String, maximum: String) -> some View { HStack { Text(label); Spacer(); Text(maximum) }.font(.system(size: 11)).foregroundStyle(.secondary) }
    private var timeAxis: some View { HStack { Text("\(Int(max(60, (dates.last ?? Date()).timeIntervalSince(dates.first ?? Date())))) seconds"); Spacer(); Text("0") }.font(.system(size: 10)).foregroundStyle(.secondary) }
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
}

struct ResourcePlot: View {
    let values: [Double?]
    var dates: [Date] = []
    var secondValues: [Double?] = []
    var maximum: Double = 100
    var color: Color = .blue
    var compact = false
    var overlays: [ResourcePlotOverlay] = []
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(color.opacity(0.035)))
            var grid = Path()
            for i in 0...10 { let x = size.width * Double(i) / 10; grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
            for i in 0...5 { let y = size.height * Double(i) / 5; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
            context.stroke(grid, with: .color(color.opacity(compact ? 0.09 : 0.13)), lineWidth: 0.5)
            draw(values, size: size, context: &context, dashed: false)
            if !secondValues.isEmpty { draw(secondValues, size: size, context: &context, dashed: true) }
            for overlay in overlays {
                draw(overlay.values, size: size, context: &context, dashed: true, lineColor: overlay.color, lineDash: overlay.dash)
            }
            context.stroke(Path(rect), with: .color(color.opacity(0.3)), lineWidth: 1)
        }
    }
    private func draw(_ values: [Double?], size: CGSize, context: inout GraphicsContext, dashed: Bool, lineColor: Color? = nil, lineDash: [CGFloat]? = nil) {
        guard values.count > 1 else { return }
        let capacity = max(values.count, compact ? 30 : 60)
        let timed = dates.count == values.count
        let end = dates.last?.timeIntervalSince1970 ?? 0
        let duration = timed ? max(60, end - (dates.first?.timeIntervalSince1970 ?? end)) : 1
        var segments: [[CGPoint]] = []
        var segment: [CGPoint] = []
        for (index, value) in values.enumerated() {
            let gap = timed && index > 0 && dates[index].timeIntervalSince(dates[index - 1]) > 6
            if gap || value == nil || value?.isFinite == false {
                if !segment.isEmpty { segments.append(segment); segment.removeAll(keepingCapacity: true) }
            }
            guard let value, value.isFinite else { continue }
            let x = timed ? size.width * (1 - (end - dates[index].timeIntervalSince1970) / duration) : size.width * Double(capacity - values.count + index) / Double(capacity - 1)
            let y = size.height * (1 - min(1, max(0, value / max(1, maximum))))
            segment.append(CGPoint(x: x, y: y))
        }
        if !segment.isEmpty { segments.append(segment) }
        for points in segments {
            guard points.count > 1, let first = points.first, let last = points.last else { continue }
            var line = Path(); line.move(to: first)
            points.dropFirst().forEach { line.addLine(to: $0) }
            if !dashed {
                var fill = line; fill.addLine(to: CGPoint(x: last.x, y: size.height)); fill.addLine(to: CGPoint(x: first.x, y: size.height)); fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0.025)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color((lineColor ?? color).opacity(lineColor != nil ? 0.95 : dashed ? 0.55 : 0.9)), style: StrokeStyle(lineWidth: compact ? 1 : 1.6, lineJoin: .round, dash: lineDash ?? (dashed ? [4, 3] : [])))
        }
    }
}
