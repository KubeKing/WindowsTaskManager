import AppKit
import SwiftUI
import TaskManagerCore

@main
enum AppMain {
    @MainActor static func main() {
        // An optional diagnostic run samples real local data without creating a UI.
        if CommandLine.arguments.contains("--sample") {
            let sampler = SystemSampler()
            let temperatures = CommandLine.arguments.contains("--temperatures")
            _ = sampler.sample(includeTemperatures: temperatures); Thread.sleep(forTimeInterval: 1)
            _ = sampler.sample(includeTemperatures: temperatures); Thread.sleep(forTimeInterval: 1)
            let value = sampler.sample(includeTemperatures: temperatures)
            print("Processes: \(value.processes.count), CPU: \(value.cpuUsage.map { String(format: "%.2f%%", $0) } ?? "unavailable"), memory: \(value.memory.usedBytes)/\(value.memory.totalBytes), sampler: \(String(format: "%.2f ms", value.collectionDuration * 1000))")
            print("Per-process network: \(value.processes.filter { $0.networkBytesPerSecond != nil }.count) attributed processes, \(MetricFormat.rate(value.processes.compactMap(\.networkBytesPerSecond).reduce(0, +))) observed TCP/UDP")
            print("CPU: \(value.cpuName), cores: \(value.logicalCPUCount), interfaces: \(value.networks.map(\.name)), disks: \(value.disks.map(\.mountPath))")
            print("CPU frequency (experimental): P=\(value.cpuFrequency.performanceMHz.map { String(format: "%.0f MHz", $0) } ?? "unavailable"), E=\(value.cpuFrequency.efficiencyMHz.map { String(format: "%.0f MHz", $0) } ?? "unavailable")")
            for disk in value.disks { print("Storage: \(disk.name) · \(disk.bsdName ?? "unknown") · \(disk.kind.rawValue) · capacity=\(disk.totalBytes) · volumes=\(disk.volumes.count) · used=\(disk.primaryVolume?.usedBytes.description ?? "unavailable")") }
            for gpu in value.gpus {
                print("GPU: \(gpu.name), utilization: \(MetricFormat.percent(gpu.utilization)), renderer: \(MetricFormat.percent(gpu.rendererUtilization)), tiler: \(MetricFormat.percent(gpu.tilerUtilization)), memory in use: \(MetricFormat.bytes(gpu.memoryInUseBytes)), allocated: \(MetricFormat.bytes(gpu.memoryAllocatedBytes))")
            }
            if temperatures {
                let t = value.temperatures
                print("Temperature sensor averages: CPU=\(t.cpuAverageCelsius.map { String(format: "%.1f C", $0) } ?? "unavailable") (\(t.cpuSensorCount) sensors), GPU=\(t.gpuAverageCelsius.map { String(format: "%.1f C", $0) } ?? "unavailable") (\(t.gpuSensorCount) sensors); verified per-core mappings=\(t.logicalCoreCelsius.count)")
            }
            value.warnings.forEach { print("Note: \($0)") }
            return
        }
        let app = NSApplication.shared
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            app.applicationIconImage = icon
        }
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = MonitorStore()
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Task Manager"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.toolbarStyle = .unified
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.minSize = NSSize(width: 900, height: 630)
        window.tabbingMode = .disallowed; window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(store: store))
        window.center(); window.setFrameAutosaveName("TaskManagerMainWindow")
        if store.alwaysOnTop { window.level = .floating }
        installMenus()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { store.stop() }
    func applicationDidHide(_ notification: Notification) { store.setVisible(false) }
    func applicationDidUnhide(_ notification: Notification) { updateVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { store.setVisible(false) }
    func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    private func updateVisibility() { store.setVisible(!NSApp.isHidden && !window.isMiniaturized && window.occlusionState.contains(.visible)) }

    private func item(_ title: String, _ selector: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers
        return item
    }
    private func installMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let app = NSMenu(title: "Task Manager"); appItem.submenu = app
        app.addItem(item("About Task Manager", #selector(about)))
        app.addItem(.separator()); app.addItem(item("Settings…", #selector(settings), ","))
        app.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Task Manager", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"); app.addItem(hide)
        app.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        app.addItem(.separator()); app.addItem(NSMenuItem(title: "Quit Task Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let fileItem = NSMenuItem(); fileItem.submenu = NSMenu(title: "File"); menu.addItem(fileItem)
        fileItem.submenu?.addItem(item("Run New Task…", #selector(runTask), "n"))
        let editItem = NSMenuItem(); editItem.submenu = NSMenu(title: "Edit"); menu.addItem(editItem)
        editItem.submenu?.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editItem.submenu?.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editItem.submenu?.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu?.addItem(item("Copy Process Details", #selector(copyProcess), "c", modifiers: [.command, .shift]))
        let viewItem = NSMenuItem(); viewItem.submenu = NSMenu(title: "View"); menu.addItem(viewItem)
        viewItem.submenu?.addItem(item("Refresh Now", #selector(refresh), "r"))
        viewItem.submenu?.addItem(item("Pause / Resume Monitoring", #selector(pause), "p", modifiers: [.command, .shift]))
        viewItem.submenu?.addItem(.separator())
        for page in ManagerPage.allCases {
            let row = item(page.title, #selector(selectPage(_:))); row.representedObject = page.rawValue
            viewItem.submenu?.addItem(row)
        }
        let processItem = NSMenuItem(); processItem.submenu = NSMenu(title: "Process"); menu.addItem(processItem)
        processItem.submenu?.addItem(item("Inspect Process…", #selector(inspect), "i"))
        processItem.submenu?.addItem(item("Show in Finder", #selector(reveal)))
        processItem.submenu?.addItem(.separator()); processItem.submenu?.addItem(item("Quit Process…", #selector(quitProcess)))
        processItem.submenu?.addItem(item("Force Quit…", #selector(forceQuit), "\u{8}"))
        let windowItem = NSMenuItem(); let windows = NSMenu(title: "Window"); windowItem.submenu = windows; menu.addItem(windowItem)
        windows.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windows.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windows; NSApp.mainMenu = menu
    }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Task Manager", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development", .credits: NSAttributedString(string: "A local system monitor for your Mac.\nBuilt with Swift and Apple frameworks.\nNo accounts, telemetry, or network connections.")]) }
    @objc private func settings() { store.page = .settings }
    @objc private func runTask() { store.launchApplication() }
    @objc private func refresh() { store.refresh() }
    @objc private func pause() { store.togglePause() }
    @objc private func copyProcess() { store.copySelected() }
    @objc private func inspect() { store.inspectSelected() }
    @objc private func reveal() { store.revealSelected() }
    @objc private func quitProcess() { store.quitSelected(force: false) }
    @objc private func forceQuit() { store.quitSelected(force: true) }
    @objc private func selectPage(_ sender: NSMenuItem) { if let name = sender.representedObject as? String, let page = ManagerPage(rawValue: name) { store.page = page } }
}
