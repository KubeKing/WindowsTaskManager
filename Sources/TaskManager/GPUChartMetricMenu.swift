import AppKit
import SwiftUI
import TaskManagerCore

/// A native pull-down snapshots its entries when opened. Live sampling updates
/// only the next provider; it never rebuilds a menu AppKit is currently tracking.
struct GPUChartMetricMenu: NSViewRepresentable {
    let slot: Int
    let selected: GPUChartMetric
    let gpu: GPUMetrics?
    let onSelect: (GPUChartMetric) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false; button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = .secondaryLabelColor
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel("GPU chart \(slot + 1) metric")
        button.toolTip = "Choose the metric for this chart. Choices are saved across app updates."
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.delegate = context.coordinator; button.menu = menu
        context.coordinator.populate(menu)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.owner = self
        if !context.coordinator.tracking { button.item(at: 0)?.title = selected.title }
    }
    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var owner: GPUChartMetricMenu
        private(set) var tracking = false
        init(owner: GPUChartMetricMenu) { self.owner = owner }
        func menuWillOpen(_ menu: NSMenu) { tracking = true; populate(menu) }
        func menuDidClose(_ menu: NSMenu) { tracking = false }
        func populate(_ menu: NSMenu) {
            menu.removeAllItems()
            menu.addItem(NSMenuItem(title: owner.selected.title, action: nil, keyEquivalent: ""))
            for metric in GPUChartMetric.allCases {
                let unavailable = metric.value(in: owner.gpu) == nil
                let item = NSMenuItem(title: metric.title + (unavailable ? " — unavailable" : ""), action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = metric.rawValue
                item.state = metric == owner.selected ? .on : .off
                item.toolTip = unavailable ? metric.unavailableReason : nil
                menu.addItem(item)
            }
        }
        @objc private func choose(_ item: NSMenuItem) {
            guard let raw = item.representedObject as? String, let metric = GPUChartMetric(rawValue: raw) else { return }
            owner.onSelect(metric)
        }
    }
}
