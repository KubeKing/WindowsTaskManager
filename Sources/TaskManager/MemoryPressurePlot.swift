import SwiftUI
import TaskManagerCore

/// A categorical history of native pressure states; no invented pressure percentage.
struct MemoryPressurePlot: View {
    let history: [HistoryPoint]
    let current: MemoryPressureLevel?
    @Environment(\.graphTimeWindow) private var graphWindow

    private func color(_ level: MemoryPressureLevel?) -> Color {
        switch level {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case nil: return .secondary
        }
    }
    private func height(_ level: MemoryPressureLevel) -> Double {
        switch level {
        case .normal: return 1.0 / 3
        case .warning: return 2.0 / 3
        case .critical: return 1
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
                let rect = CGRect(x: 0.5, y: 0.5, width: max(1, size.width - 59), height: max(1, size.height - 1))
                context.fill(Path(rect), with: .color(.primary.opacity(0.025)))
                var grid = Path()
                for i in 1..<10 {
                    let x = rect.minX + rect.width * Double(i) / 10
                    grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                for level in MemoryPressureLevel.allCases {
                    let y = rect.maxY - rect.height * height(level)
                    grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y))
                    context.draw(Text(level.rawValue).font(.system(size: 9)).foregroundColor(.secondary),
                                 at: CGPoint(x: rect.maxX + 6, y: y), anchor: level == .critical ? .topLeading : .leading)
                }
                context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
                let timeline = GraphTimeline(end: history.last?.timestamp ?? Date(timeIntervalSince1970: 0), window: graphWindow)
                if history.count > 1 {
                    for index in 0..<(history.count - 1) {
                        let first = history[index], next = history[index + 1]
                        let interval = next.timestamp.timeIntervalSince(first.timestamp)
                        guard let level = first.memoryPressure, interval > 0, interval <= 6,
                              let start = timeline.position(first.timestamp), let end = timeline.position(next.timestamp) else { continue }
                        let x0 = rect.minX + rect.width * min(1, max(0, start))
                        let x1 = rect.minX + rect.width * min(1, max(0, end))
                        guard x1 > x0 else { continue }
                        let y = rect.maxY - rect.height * height(level)
                        context.fill(Path(CGRect(x: x0, y: y, width: x1 - x0, height: rect.maxY - y)), with: .color(color(level).opacity(0.28)))
                        var line = Path(); line.move(to: CGPoint(x: x0, y: y)); line.addLine(to: CGPoint(x: x1, y: y))
                        if let nextLevel = next.memoryPressure {
                            line.addLine(to: CGPoint(x: x1, y: rect.maxY - rect.height * height(nextLevel)))
                        }
                        context.stroke(line, with: .color(color(level)), lineWidth: 1.4)
                    }
                }
                context.stroke(Path(rect), with: .color(.secondary.opacity(0.45)), lineWidth: 1)
            }
            .overlay {
                if !history.contains(where: { $0.memoryPressure != nil }) {
                    Text("Unavailable").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Memory pressure history")
            .accessibilityValue(current?.rawValue ?? "Unavailable")
        }
        .help("macOS memory pressure over time: green is Normal, yellow is Warning, and red is Critical. This shows pressure states, not the percentage of RAM used. Missing readings and sampling gaps are left blank.")
    }
}
