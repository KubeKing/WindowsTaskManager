import AppKit
import SwiftUI

/// Transparent to normal clicks and scrolling. Right-click menus are built once
/// per opening and owned by AppKit throughout tracking, including submenus.
struct StableContextMenu: NSViewRepresentable {
    indirect enum Entry {
        case action(String, checked: Bool? = nil, () -> Void)
        case submenu(String, [Entry])
    }
    var entries: () -> [Entry]

    func makeNSView(context: Context) -> MenuView {
        let view = MenuView()
        view.entries = entries
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: MenuView, context: Context) {
        // Update only the provider for the next opening, never the tracked menu.
        view.entries = entries
    }

    final class MenuView: NSView {
        var entries: () -> [Entry] = { [] }
        private var actions: [() -> Void] = []

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || event.type == .rightMouseUp ||
                    event.type == .leftMouseDown && event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { showMenu(event) }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { showMenu(event) }
        }
        private func showMenu(_ event: NSEvent) {
            actions.removeAll(keepingCapacity: true)
            let menu = build(entries())
            defer { actions.removeAll(keepingCapacity: true) }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        private func build(_ entries: [Entry]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for entry in entries {
                switch entry {
                case let .action(title, checked, action):
                    let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
                    item.target = self; item.tag = actions.count
                    if let checked { item.state = checked ? .on : .off }
                    actions.append(action); menu.addItem(item)
                case let .submenu(title, children):
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.submenu = build(children); menu.addItem(item)
                }
            }
            return menu
        }
        @objc private func invoke(_ item: NSMenuItem) {
            guard actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
        }
    }
}
