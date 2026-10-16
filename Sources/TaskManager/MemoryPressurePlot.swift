import SwiftUI
import TaskManagerCore

/// Granular kernel pressure height with the native pressure state as its color.
struct MemoryPressurePlot: View {
    let history: [HistoryPoint]
    let current: MemoryPressureLevel?
    let currentPercent: Double?
    @Environment(\.graphTimeWindow) private var graphWindow

    private func color(_ level: MemoryPressureLevel?) -> Color {
        switch level {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case nil: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("Memory pressure").foregroundStyle(.secondary)
                Spacer()
                Text(current?.rawValue ?? "Unavailable").foregroundStyle(color(current))
            }.font(.system(size: 11))
            Canvas { context, size in
                let rect = CGRect(x: 0.5, y: 0.5, width: max(1, size.width - 35), height: max(1, size.height - 1))
                context.fill(Path(rect), with: .color(.primary.opacity(0.025)))
                var grid = Path()
                for i in 1..<10 {
                    let x = rect.minX + rect.width * Double(i) / 10
                    grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                for value in [0.0, 50, 100] {
                    let y = rect.maxY - rect.height * value / 100
                    grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y))
                    context.draw(Text("\(Int(value))%").font(.system(size: 9)).foregroundColor(.secondary),
                                 at: CGPoint(x: rect.maxX + 6, y: y), anchor: value == 100 ? .topLeading : value == 0 ? .bottomLeading : .leading)
                }
                context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
                let timeline = GraphTimeline(end: history.last?.timestamp ?? Date(timeIntervalSince1970: 0), window: graphWindow)
                var plotContext = context
                plotContext.clip(to: Path(rect))
                if history.count > 1 {
                    for index in 0..<(history.count - 1) {
                        let first = history[index], next = history[index + 1]
                        let interval = next.timestamp.timeIntervalSince(first.timestamp)
                        guard let value = first.memoryPressurePercent, let nextValue = next.memoryPressurePercent,
                              value.isFinite, nextValue.isFinite, (0...100).contains(value), (0...100).contains(nextValue),
                              interval > 0, interval <= 6,
                              let start = timeline.position(first.timestamp), let end = timeline.position(next.timestamp) else { continue }
                        guard end >= 0, start <= 1 else { continue }
                        let x0 = rect.minX + rect.width * start, x1 = rect.minX + rect.width * end
                        let y0 = rect.maxY - rect.height * value / 100, y1 = rect.maxY - rect.height * nextValue / 100
                        var fill = Path()
                        fill.move(to: CGPoint(x: x0, y: rect.maxY)); fill.addLine(to: CGPoint(x: x0, y: y0))
                        fill.addLine(to: CGPoint(x: x1, y: y1)); fill.addLine(to: CGPoint(x: x1, y: rect.maxY)); fill.closeSubpath()
                        plotContext.fill(fill, with: .color(color(first.memoryPressure).opacity(0.28)))
                        var line = Path(); line.move(to: CGPoint(x: x0, y: y0)); line.addLine(to: CGPoint(x: x1, y: y1))
                        plotContext.stroke(line, with: .color(color(first.memoryPressure)), lineWidth: 1.4)
                    }
                }
                context.stroke(Path(rect), with: .color(.secondary.opacity(0.45)), lineWidth: 1)
            }
            .overlay {
                if !history.contains(where: { $0.memoryPressurePercent != nil }) {
                    Text("Unavailable").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Memory pressure history")
            .accessibilityValue(currentPercent.map { "\(Int($0)) percent, \(current?.rawValue ?? "pressure state unavailable")" } ?? "Unavailable")
        }
        .help("Curve height uses the same granular kernel reading as Activity Monitor: 100 minus the available-memory level. Color is macOS's separate pressure state: green Normal, yellow Warning, red Critical; gray means the color state is unavailable. This is independent of RAM-used percentage. Missing readings and sampling gaps stay blank.")
    }
}
