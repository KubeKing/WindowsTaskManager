import AppKit
import SwiftUI
import TaskManagerCore

// The macOS 27 SDK also exports a State macro whose plugin is absent from CLT.
// This explicit type alias selects the built-in property wrapper.
typealias ViewState<Value> = SwiftUI.State<Value>

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.material = material }
}

enum MetricFormat {
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        if value == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value == 0 { return "0 KB/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .decimal) + "/s"
    }
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "—" }
    static func uptime(_ interval: Double) -> String {
        let seconds = Int(max(0, interval)); let days = seconds / 86400
        return String(format: "%d:%02d:%02d:%02d", days, seconds / 3600 % 24, seconds / 60 % 60, seconds % 60)
    }
}

struct MetricValue: View {
    let title: String
    let value: String
    var color: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
    }
}

struct CapabilityNote: View {
    var text: String
    var symbol: String = "info.circle"
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}
