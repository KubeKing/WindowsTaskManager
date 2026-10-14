import AppKit
import SwiftUI

/// Menu contents are a snapshot taken at open, never rebuilt by monitoring ticks.
struct MoreMenu: NSViewRepresentable {
    let store: MonitorStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.setAccessibilityLabel("More")
        button.toolTip = "View and monitoring options"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        button.menu = menu
        context.coordinator.populate(menu)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.store = store
        // Do not touch the open NSMenu, its submenus or their selected items.
    }
    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var store: MonitorStore
        private var actions: [() -> Void] = []
        init(store: MonitorStore) { self.store = store }
        func menuWillOpen(_ menu: NSMenu) { populate(menu) }
        @objc private func invoke(_ item: NSMenuItem) {
            guard actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
        }
        private func item(_ title: String, in menu: NSMenu, checked: Bool? = nil, enabled: Bool = true, action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
            item.target = self; item.tag = actions.count; item.isEnabled = enabled
            if let checked { item.state = checked ? .on : .off }
            actions.append(action); menu.addItem(item)
        }
        private func submenu(_ title: String, in parent: NSMenu, build: (NSMenu) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title); menu.autoenablesItems = false
            build(menu); item.submenu = menu; parent.addItem(item)
        }
        func populate(_ menu: NSMenu) {
            let store = self.store
            menu.removeAllItems(); actions.removeAll(keepingCapacity: true)
            let title = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            title.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
            menu.addItem(title) // Pull-down buttons reserve the first item for their label.
            item("Refresh now", in: menu) {
                store.refresh()
                if [.startup, .services, .users].contains(store.page) { store.refreshInventory() }
            }
            item(store.isPaused ? "Resume monitoring" : "Pause monitoring", in: menu) { store.togglePause() }
            submenu("Real-time update speed", in: menu) { sub in
                for value in [0.5, 1.0, 2.0, 5.0] {
                    item("\(value.formatted()) seconds", in: sub, checked: value == store.interval) { store.setInterval(value) }
                }
            }
            if store.page == .processes || store.page == .details {
                menu.addItem(.separator())
                item("Inspect process", in: menu, enabled: store.selectedProcess != nil) { store.inspectSelected() }
                item("Reveal executable", in: menu, enabled: store.selectedProcess?.executablePath != nil) { store.revealSelected() }
                item("Copy details", in: menu, enabled: store.selectedProcess != nil) { store.copySelected() }
                submenu("CPU priority", in: menu) { sub in
                    let priorities: [(String, Int32)] = [("Normal (0)", 0), ("Low (10)", 10), ("Lowest (19)", 19), ("High (−10)", -10)]
                    for (title, nice) in priorities {
                        item(title, in: sub, enabled: store.canTerminateSelected) { store.changePriority(nice) }
                    }
                }
                item("Force quit…", in: menu, enabled: store.canTerminateSelected) { store.quitSelected(force: true) }
            }
            if store.page == .performance {
                menu.addItem(.separator())
                submenu("CPU graph", in: menu) { sub in
                    item("Overall utilization", in: sub, checked: !store.cpuGraphLogical) { store.cpuGraphLogical = false }
                    item("Logical processors", in: sub, checked: store.cpuGraphLogical) { store.cpuGraphLogical = true }
                }
                item("Show kernel times", in: menu, checked: store.showKernelTimes) { store.showKernelTimes.toggle() }
                submenu("Performance items", in: menu) { sub in
                    for resource in store.performanceItems {
                        item(resource.title, in: sub, checked: store.performanceVisibility.isShown(resource)) {
                            store.setPerformanceItem(resource, shown: !store.performanceVisibility.isShown(resource))
                        }
                    }
                    sub.addItem(.separator())
                    item("Show all performance items", in: sub) { store.showAllPerformanceItems() }
                }
            }
            let warnings = store.snapshot.warnings
            if !warnings.isEmpty {
                menu.addItem(.separator())
                item("Collection notes…", in: menu) { store.errorMessage = warnings.joined(separator: "\n\n") }
            }
        }
    }
}
