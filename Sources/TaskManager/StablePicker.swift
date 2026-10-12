import AppKit
import SwiftUI

/// Fixed-choice native picker whose menu is not rebuilt by monitoring updates.
struct StablePicker<Value: Equatable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let choices: [(String, Value)]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.addItems(withTitles: choices.map { $0.0 })
        button.setAccessibilityLabel(title)
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.owner = self
        if let index = choices.firstIndex(where: { $0.1 == selection }), index != button.indexOfSelectedItem {
            button.selectItem(at: index)
        }
    }
    @MainActor final class Coordinator: NSObject {
        var owner: StablePicker
        init(_ owner: StablePicker) { self.owner = owner }
        @objc func choose(_ button: NSPopUpButton) {
            let index = button.indexOfSelectedItem
            guard owner.choices.indices.contains(index) else { return }
            owner.selection = owner.choices[index].1
        }
    }
}
