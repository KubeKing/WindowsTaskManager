import AppKit
import Combine
import SwiftUI
import TaskManagerCore

enum ManagerPage: String, CaseIterable, Identifiable {
    case processes, performance, appHistory, startup, users, details, services, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .processes: return "Processes"
        case .performance: return "Performance"
        case .appHistory: return "App history"
        case .startup: return "Startup apps"
        case .users: return "Users"
        case .details: return "Details"
        case .services: return "Services"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .processes: return "square.stack.3d.up"
        case .performance: return "waveform.path.ecg"
        case .appHistory: return "clock.arrow.circlepath"
        case .startup: return "power"
        case .users: return "person.2"
        case .details: return "list.bullet.rectangle"
        case .services: return "gearshape.2"
        case .settings: return "gearshape"
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case macOS, windows
    var title: String { self == .macOS ? "macOS" : "Windows" }
}

/// The contained sampler is accessed exclusively on MonitorStore's serial worker.
private final class SamplingContext: @unchecked Sendable {
    let sampler = SystemSampler()
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var history: [HistoryPoint] = []
    @Published var page: ManagerPage = .processes { didSet { loadInventoryIfNeeded() } }
    @Published var defaultStartPage: ManagerPage { didSet { defaults.set(defaultStartPage.rawValue, forKey: "defaultStartPage") } }
    @Published var performanceSelection = "cpu"
    @Published var cpuGraphLogical = false
    @Published var showKernelTimes = false
    @Published var graphWindow: GraphTimeWindow { didSet {
        graphWindow.save(defaults)
        history = GraphHistory.visible(graphBuffer, seconds: graphWindow.rawValue)
    } }
    @Published var showTemperatures: Bool { didSet {
        defaults.set(showTemperatures, forKey: "showTemperatures.v1")
        refresh()
    } }
    @Published private(set) var performanceVisibility: PerformanceVisibility
    @Published private(set) var gpuChartLayout: GPUChartLayout
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var query = "" { didSet {
        if let selection, !ProcessQuery.filter(snapshot.processes, query: query).contains(where: { $0.id == selection }) { self.selection = nil }
    } }
    @Published var isPaused = false
    @Published var interval: Double { didSet {
        if ![0.5, 1, 2, 5].contains(interval) { interval = 1 }
        defaults.set(interval, forKey: "interval"); schedule()
    } }
    @Published var selection: ProcessIdentity?
    @Published var errorMessage: String?
    @Published var inventory = InventorySnapshot()
    @Published var historyRecords: [AppHistoryRecord] = []
    @Published var historyEnabled: Bool { didSet {
        defaults.set(historyEnabled, forKey: "historyEnabled")
        localHistory.resetBaseline()
    } }
    @Published var alwaysOnTop: Bool { didSet {
        defaults.set(alwaysOnTop, forKey: "alwaysOnTop")
        NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.level = alwaysOnTop ? .floating : .normal }
    } }
    @Published var colorSchemeChoice: String { didSet { defaults.set(colorSchemeChoice, forKey: "colorScheme") } }
    private(set) var isCollecting = false
    private let defaults: UserDefaults
    private let samplingContext = SamplingContext()
    private let worker = DispatchQueue(label: "local.taskmanager.collection", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var windowVisible = true
    private var inventoryBusy = false
    private var lastInventoryRefresh = Date.distantPast
    private var localHistory: LocalHistory
    private var lastHistorySave = Date.distantPast
    private var latestSnapshot: SystemSnapshot?
    private var graphBuffer: [HistoryPoint] = []
    private var lastHistoryMaintenance = Date.distantPast
    private var pauseGap: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        performanceVisibility = PerformanceVisibility(defaults: defaults)
        gpuChartLayout = GPUChartLayout(defaults: defaults)
        graphWindow = GraphTimeWindow.load(defaults)
        showTemperatures = defaults.bool(forKey: "showTemperatures.v1")
        let initialPage = ManagerPage(rawValue: defaults.string(forKey: "defaultStartPage") ?? "") ?? .processes
        defaultStartPage = initialPage
        page = initialPage
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .macOS
        let storedInterval = defaults.double(forKey: "interval")
        interval = [0.5, 1, 2, 5].contains(storedInterval) ? storedInterval : 1
        historyEnabled = defaults.bool(forKey: "historyEnabled")
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        colorSchemeChoice = defaults.string(forKey: "colorScheme") ?? "system"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskManager", isDirectory: true)
        localHistory = LocalHistory(directory: directory)
        historyRecords = localHistory.records
        if let error = localHistory.lastError { errorMessage = error }
    }

    var selectedProcess: ProcessRecord? { snapshot.processes.first { $0.id == selection } }
    var canTerminateSelected: Bool {
        guard let record = selectedProcess else { return false }
        return record.id.pid > 1 && record.id.pid != ProcessInfo.processInfo.processIdentifier && !["launchd", "kernel_task", "WindowServer", "loginwindow", "watchdogd"].contains(record.name)
    }
    // The table owns sorting; sorting again here doubled work on every tick.
    var visibleProcesses: [ProcessRecord] { ProcessQuery.filter(snapshot.processes, query: query) }
    var appCount: Int { Set(snapshot.processes.compactMap(\.applicationPath)).count }
    var totalNetworkRate: Double? {
        let rates = snapshot.networks.flatMap { [$0.receiveBytesPerSecond, $0.sendBytesPerSecond].compactMap { $0 } }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }
    var totalDiskRate: Double? {
        let rates = snapshot.processes.flatMap { [$0.readBytesPerSecond, $0.writeBytesPerSecond].compactMap { $0 } }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }
    var actualInterval: Double { windowVisible ? interval : max(5, interval) }
    var historyObservationStart: Date? { localHistory.observationStart }

    func start() { maintainHistory(); schedule(); loadInventoryIfNeeded() }
    private func loadInventoryIfNeeded() {
        if [.startup, .services, .users].contains(page), Date().timeIntervalSince(lastInventoryRefresh) > 30 { refreshInventory() }
    }
    var performanceItems: [PerformanceItem] { PerformanceCatalog.items(in: snapshot) }
    var visiblePerformanceItems: [PerformanceItem] { performanceVisibility.visibleItems(in: performanceItems) }
    func setPerformanceItem(_ item: PerformanceItem, shown: Bool) {
        performanceVisibility.setShown(shown, preferenceID: item.preferenceID)
        reconcilePerformanceSelection()
    }
    func setGPUChartMetric(_ metric: GPUChartMetric, at slot: Int) { gpuChartLayout.set(metric, at: slot) }
    func showAllPerformanceItems() {
        performanceVisibility.showAll()
        reconcilePerformanceSelection()
    }
    private func reconcilePerformanceSelection() {
        if let selected = performanceVisibility.selection(performanceSelection, in: performanceItems), selected != performanceSelection {
            performanceSelection = selected
        }
    }
    func stop() {
        timer?.cancel(); timer = nil
        if historyEnabled { try? localHistory.save() }
        try? localHistory.maintain()
    }
    func setVisible(_ visible: Bool) {
        guard windowVisible != visible else { return }
        windowVisible = visible
        if visible, let latestSnapshot { publish(latestSnapshot) }
        schedule()
    }
    func togglePause() {
        isPaused.toggle()
        if isPaused { pauseGap = Date() }
        localHistory.resetBaseline(); schedule()
    }
    func setInterval(_ value: Double) { interval = value }
    func setHistoryEnabled(_ enabled: Bool) { historyEnabled = enabled }

    private func schedule() {
        timer?.cancel(); timer = nil
        guard !isPaused else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: actualInterval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer; timer.resume()
    }

    func refresh() {
        guard !isCollecting else { return }
        isCollecting = true
        let context = samplingContext
        let includeTemperatures = showTemperatures
        worker.async { [weak self] in
            let value = autoreleasepool { context.sampler.sample(includeTemperatures: includeTemperatures) }
            DispatchQueue.main.async { self?.accept(value) }
        }
    }

    private func accept(_ value: SystemSnapshot) {
        latestSnapshot = value
        if !isPaused, let pauseGap {
            var gap = HistoryPoint(snapshot: value)
            gap.timestamp = pauseGap; gap.cpu = nil; gap.memory = nil; gap.logicalCPU = []
            gap.totalMemoryBytes = nil; gap.systemUsedMemoryBytes = nil
            gap.kernelCPU = nil; gap.logicalKernel = []; gap.networkByID = [:]; gap.diskByID = [:]; gap.gpuByID = [:]
            gap.diskRead = nil; gap.diskWrite = nil; gap.networkReceived = nil; gap.networkSent = nil
            graphBuffer.append(gap); self.pauseGap = nil
        }
        graphBuffer.append(HistoryPoint(snapshot: value))
        graphBuffer = GraphHistory.retained(graphBuffer)
        if Date().timeIntervalSince(lastHistoryMaintenance) >= 60 { maintainHistory() }
        if historyEnabled && !isPaused {
            localHistory.record(snapshot: value)
            if Date().timeIntervalSince(lastHistorySave) >= 30 {
                do { try localHistory.save(); lastHistorySave = Date() }
                catch { errorMessage = "Could not save local history: \(error.localizedDescription)"; historyEnabled = false }
            }
        }
        if windowVisible { publish(value) }
        isCollecting = false
    }

    private func maintainHistory() {
        do {
            try localHistory.maintain()
            lastHistoryMaintenance = Date()
            if windowVisible { historyRecords = localHistory.records }
        } catch { errorMessage = "Could not maintain local history: \(error.localizedDescription)" }
    }

    private func publish(_ value: SystemSnapshot) {
        snapshot = value
        history = GraphHistory.visible(graphBuffer, seconds: graphWindow.rawValue)
        reconcilePerformanceSelection()
        if historyEnabled { historyRecords = localHistory.records }
        if let selection, !value.processes.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    func refreshInventory() {
        guard !inventoryBusy else { return }
        inventoryBusy = true
        worker.async { [weak self] in
            let value = SystemInventory().scan()
            DispatchQueue.main.async {
                self?.inventory = value; self?.inventoryBusy = false; self?.lastInventoryRefresh = Date()
            }
        }
    }

    func quitSelected(force: Bool) {
        guard let record = selectedProcess else { return }
        let alert = NSAlert()
        alert.messageText = force ? "Force quit “\(record.name)”?" : "Quit “\(record.name)”?"
        alert.informativeText = force ? "The process will stop immediately. Unsaved changes may be lost.\n\nProcess ID: \(record.id.pid)" : "Send a termination request to this process. Unsaved changes may be lost.\n\nProcess ID: \(record.id.pid)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: force ? "Force Quit" : "Quit Process")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try ProcessActions.terminate(record.id, force: force); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func changePriority(_ nice: Int32) {
        guard let record = selectedProcess else { return }
        do { try ProcessActions.setPriority(record.id, nice: nice) }
        catch { errorMessage = error.localizedDescription }
    }

    func revealSelected() {
        guard let path = selectedProcess?.executablePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    func copySelected() {
        guard let record = selectedProcess else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details(record), forType: .string)
    }
    func inspectSelected() {
        guard let record = selectedProcess else { return }
        let alert = NSAlert(); alert.messageText = record.name; alert.informativeText = details(record)
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy")
        if record.executablePath != nil { alert.addButton(withTitle: "Show in Finder") }
        let choice = alert.runModal()
        if choice == .alertSecondButtonReturn { copySelected() }
        else if choice == .alertThirdButtonReturn { revealSelected() }
    }
    private func details(_ record: ProcessRecord) -> String {
        let start = Date(timeIntervalSince1970: Double(record.id.startTime) / 1_000_000)
        let memory = record.memoryBytes.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? "Unavailable"
        let cpu = record.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Unavailable"
        return "PID: \(record.id.pid)\nUser: \(record.user)\nCPU: \(cpu) (whole machine)\nMemory: \(memory)\nThreads: \(record.threadCount.map(String.init) ?? "Unavailable")\nStarted: \(start.formatted())\nExecutable: \(record.executablePath ?? "Permission restricted")"
    }
    func launchApplication() {
        let panel = NSOpenPanel(); panel.title = "Run New Task"; panel.prompt = "Run"
        panel.message = "Choose an application or executable to launch on this Mac."
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.pathExtension == "app" {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
            }
        } else {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { errorMessage = "Choose an application or an executable file."; return }
            do { let process = Process(); process.executableURL = url; try process.run() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func clearHistory() {
        let alert = NSAlert(); alert.messageText = "Clear app history?"
        alert.informativeText = "Delete resource usage recorded by Task Manager on this Mac."
        alert.addButton(withTitle: "Clear History"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try localHistory.clear(); historyRecords = localHistory.records }
        catch { errorMessage = error.localizedDescription }
    }
}
