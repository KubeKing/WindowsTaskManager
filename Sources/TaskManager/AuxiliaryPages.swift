import AppKit
import SwiftUI
import TaskManagerCore

struct InventoryPage: View {
    @ObservedObject var store: MonitorStore
    let kind: ManagerPage
    private var entries: [InventoryEntry] {
        let source = kind == .startup ? store.inventory.startup : kind == .users ? store.inventory.sessions : store.inventory.services
        let filtered = source.filter { store.query.isEmpty || "\($0.name) \($0.detail) \($0.state) \($0.owner ?? "")".localizedCaseInsensitiveContains(store.query) }
        if kind == .users {
            // Windows groups sessions by user, so never repeat a user's resource totals.
            var seen = Set<String>()
            return filtered.filter { seen.insert($0.name).inserted }
        }
        return filtered
    }
    private var columns: [AuxiliaryColumn] {
        switch kind {
        case .startup: return [.init("name", "Name", 280), .init("publisher", "Publisher", 180), .init("status", "Status", 115), .init("impact", "Startup impact", 120), .init("kind", "Startup type", 130, optional: true), .init("path", "Command line", 280, optional: true)]
        case .users: return [.init("name", "User", 260), .init("status", "Status", 110), .init("cpu", "CPU", 85, metric: true), .init("memory", "Memory", 100, metric: true), .init("disk", "Disk", 90, metric: true), .init("network", "Network", 90, metric: true), .init("session", "Session", 160, optional: true)]
        default: return [.init("name", "Name", 245), .init("pid", "PID", 65), .init("description", "Description", 265), .init("status", "Status", 115), .init("group", "Group", 135)]
        }
    }
    private var rows: [AuxiliaryRow] {
        entries.map { entry in
            var values = ["name": entry.name, "status": compactState(entry.state), "path": entry.detail, "kind": entry.kind]
            var children: [AuxiliaryRow] = []
            var sortValues: [String: Double] = [:]
            if kind == .users {
                let processes = store.snapshot.processes.filter { $0.user == entry.name }
                values["name"] = "\(entry.name) (\(processes.count))"
                values["session"] = store.inventory.sessions.filter { $0.name == entry.name }.map(\.detail).joined(separator: ", ")
                values["cpu"] = MetricFormat.percent(sum(processes.map(\.cpuPercent)))
                values["memory"] = MetricFormat.bytes(sum(processes.map { $0.memoryBytes.map { Double($0) } }).map { UInt64(max(0, $0)) })
                values["disk"] = MetricFormat.rate(sum(processes.map { p in
                    guard let read = p.readBytesPerSecond, let write = p.writeBytesPerSecond else { return nil }; return read + write
                }))
                values["network"] = MetricFormat.rate(sum(processes.map(\.networkBytesPerSecond)))
                sortValues["network"] = sum(processes.map(\.networkBytesPerSecond))
                sortValues["cpu"] = sum(processes.map(\.cpuPercent))
                sortValues["memory"] = sum(processes.map { $0.memoryBytes.map { Double($0) } })
                sortValues["disk"] = sum(processes.map { p in p.readBytesPerSecond.flatMap { read in p.writeBytesPerSecond.map { read + $0 } } })
                children = processes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { p in
                    AuxiliaryRow(id: "process:\(p.id.pid):\(p.id.startTime)", values: ["name": p.name, "status": p.status ?? "—", "cpu": MetricFormat.percent(p.cpuPercent), "memory": MetricFormat.bytes(p.memoryBytes), "disk": MetricFormat.rate(p.readBytesPerSecond.flatMap { read in p.writeBytesPerSecond.map { read + $0 } }), "network": MetricFormat.rate(p.networkBytesPerSecond)], path: p.executablePath, iconPath: p.applicationPath ?? p.executablePath, symbol: "gearshape", processID: p.id, sortValues: ["network": p.networkBytesPerSecond ?? -1, "cpu": p.cpuPercent ?? -1, "memory": p.memoryBytes.map { Double($0) } ?? -1, "disk": p.readBytesPerSecond.flatMap { read in p.writeBytesPerSecond.map { read + $0 } } ?? -1])
                }
            } else if kind == .startup {
                // The configured executable is not evidence of a signed publisher or a boot measurement.
                values["publisher"] = "—"; values["impact"] = "Not measured"
            } else {
                values["pid"] = entry.state.components(separatedBy: "PID ").last.flatMap { Int32($0) }.map(String.init) ?? "—"
                values["description"] = entry.detail
                values["group"] = entry.kind
            }
            return AuxiliaryRow(id: entry.id, values: values, path: entry.path, symbol: kind == .users ? "person.crop.circle" : kind == .startup ? "app" : "gearshape.2", children: children, sortValues: sortValues)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            AuxiliaryTable(columns: columns, rows: rows, appearance: store.appearance, headerTotals: kind == .users ? ["cpu": MetricFormat.percent(store.snapshot.cpuUsage), "memory": MetricFormat.percent(store.snapshot.memory.usedPercent), "disk": MetricFormat.rate(store.totalDiskRate), "network": MetricFormat.rate(sum(store.snapshot.processes.map(\.networkBytesPerSecond)))] : [:], onProcess: { identity in store.query = ""; store.selection = identity; store.page = .details })
            if entries.isEmpty {
                ContentUnavailableView(store.query.isEmpty ? "No accessible items" : "No matches", systemImage: "magnifyingglass", description: Text(store.query.isEmpty ? "Refresh to read the local inventory." : "Try a different search.")).frame(maxHeight: 140)
            }
            Divider()
            CapabilityNote(text: explanation)
        }.onAppear { store.refreshInventory() }
    }
    private func sum(_ values: [Double?]) -> Double? {
        let available = values.compactMap { $0 }; return available.isEmpty ? nil : available.reduce(0, +)
    }
    private func compactState(_ state: String) -> String {
        if state.hasPrefix("Running") { return "Running" }
        if state.hasPrefix("Loaded") { return "Loaded · idle" }
        if state.contains("disabled") { return "Disabled in plist" }
        if state.hasPrefix("Configured") { return "Unknown" }
        return state
    }
    private var explanation: String {
        switch kind {
        case .startup: return "Configured launch agents. Publisher and startup impact are not measured; load state does not prove startup permissions. Use Open Login Items to manage startup permissions."
        case .users: return "Expand a user to see accessible processes. Totals cover that user's accessible processes. Network totals are experimental observed TCP/UDP rates, including loopback; protected or unobserved processes remain unavailable. Disconnect controls are unavailable."
        default: return "macOS launchd jobs. PID and running state are shown only when reported by launchctl; configured system jobs have unknown runtime state. Group identifies the launchd job kind."
        }
    }
}

struct HistoryPage: View {
    @ObservedObject var store: MonitorStore
    private var records: [AppHistoryRecord] { store.historyRecords.filter { store.query.isEmpty || $0.name.localizedCaseInsensitiveContains(store.query) } }
    private var columns: [AuxiliaryColumn] { [.init("name", "Name", 260), .init("cpu", "CPU time", 100, metric: true), .init("network", "Network", 100, metric: true), .init("metered", "Metered network", 125, metric: true), .init("notifications", "Notifications", 110, metric: true), .init("read", "Disk read", 110, metric: true, optional: true), .init("written", "Disk written", 110, metric: true, optional: true), .init("seen", "Last observed", 170, optional: true)] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.historyObservationStart.map { "Resource usage observed since \($0.formatted(date: .numeric, time: .omitted)) for the current user and accessible system processes." } ?? "Resource usage has not been recorded yet.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Delete usage history") { store.clearHistory() }.buttonStyle(.link).font(.system(size: 11)).disabled(records.isEmpty)
                }
                Spacer(minLength: 10)
                Toggle("Record locally", isOn: Binding(get: { store.historyEnabled }, set: { store.setHistoryEnabled($0) })).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            AuxiliaryTable(columns: columns, rows: records.map { item in
                AuxiliaryRow(id: item.id, values: ["name": item.name, "cpu": item.cpuAvailable ? cpuTime(item.cpuSeconds) : "—", "network": "—", "metered": "—", "notifications": "—", "read": MetricFormat.bytes(item.readAvailable ? item.readBytes : nil), "written": MetricFormat.bytes(item.writeAvailable ? item.writeBytes : nil), "seen": item.lastSeen.formatted(date: .abbreviated, time: .shortened)], path: item.id.hasPrefix("/") ? item.id : nil, iconPath: item.id.hasPrefix("/") ? item.id : nil, symbol: "app", sortValues: ["cpu": item.cpuAvailable ? item.cpuSeconds : -1, "read": item.readAvailable ? Double(item.readBytes) : -1, "written": item.writeAvailable ? Double(item.writeBytes) : -1, "seen": item.lastSeen.timeIntervalSince1970])
            }, appearance: store.appearance)
            if records.isEmpty {
                ContentUnavailableView(store.historyEnabled ? "Building your history" : "History recording is off", systemImage: "clock.arrow.circlepath", description: Text("Enable Record locally to collect observed CPU time. Records stay on this Mac.")).frame(maxHeight: 160)
            }
            Divider()
            CapabilityNote(text: "Observed activity only · 30 days retained locally. Network history is not recorded in this build. Retrospective metered-network and notification history are unavailable. Right-click a column header to show observed disk activity.")
        }
    }
    private func cpuTime(_ value: Double) -> String {
        let seconds = Int(max(0, value)); return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

private struct AuxiliaryColumn: Equatable {
    let id: String
    let title: String
    let width: CGFloat
    var metric = false
    var optional = false
    init(_ id: String, _ title: String, _ width: CGFloat, metric: Bool = false, optional: Bool = false) {
        self.id = id; self.title = title; self.width = width; self.metric = metric; self.optional = optional
    }
}
private struct AuxiliaryRow: Equatable {
    let id: String
    var values: [String: String]
    var path: String? = nil
    var iconPath: String? = nil
    var symbol = "app"
    var children: [AuxiliaryRow] = []
    var processID: ProcessIdentity? = nil
    var sortValues: [String: Double] = [:]
}

/// Native, dense, draggable and sortable Task Manager tables, shared by the secondary pages.
private struct AuxiliaryTable: NSViewRepresentable {
    let columns: [AuxiliaryColumn]
    let rows: [AuxiliaryRow]
    let appearance: AppAppearance
    var headerTotals: [String: String] = [:]
    var onProcess: ((ProcessIdentity) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView(); table.style = .plain; table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false; table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.delegate = context.coordinator; table.dataSource = context.coordinator; table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openRow)
        table.allowsMultipleSelection = false
        context.coordinator.table = table
        let scroll = NSScrollView(); scroll.documentView = table
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        context.coordinator.configure()
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.owner = self; context.coordinator.configure(); context.coordinator.reload() }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var owner: AuxiliaryTable
        weak var table: NSTableView?
        struct VisibleRow: Equatable {
            let row: AuxiliaryRow
            let depth: Int
        }
        var visible: [VisibleRow] = []
        var previousRows: [AuxiliaryRow]? = nil
        var previousExpanded = Set<String>()
        var previousSortKey: String? = nil
        var previousSortAscending = true
        var configuredColumns: [AuxiliaryColumn] = []
        var needsFullReload = true
        var previousHeaderTotals: [String: String] = [:]
        var previousHeaderSortKey: String? = nil
        var previousHeaderSortAscending = true
        var expanded = Set<String>()
        var signature = ""
        var icons: [String: NSImage] = [:]
        init(_ owner: AuxiliaryTable) { self.owner = owner }
        func configure() {
            guard let table else { return }
            let next = owner.columns.map(\.id).joined(separator: ",")
            let rowHeight: CGFloat = owner.appearance == .macOS ? 27 : 24
            if table.rowHeight != rowHeight { table.rowHeight = rowHeight }
            guard configuredColumns != owner.columns else { updateHeaders(); return }
            configuredColumns = owner.columns; signature = next
            previousRows = nil; needsFullReload = true
            for column in table.tableColumns { table.removeTableColumn(column) }
            for spec in owner.columns {
                let column = NSTableColumn(identifier: .init(spec.id)); column.title = spec.title
                column.width = spec.width; column.minWidth = spec.id == "name" ? 160 : 55
                let preference = UserDefaults.standard.object(forKey: "secondaryColumn.\(next).\(spec.id)") as? Bool
                column.isHidden = spec.id == "name" ? false : (preference ?? spec.optional)
                column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
                column.headerCell = ResourceHeaderCell(textCell: spec.title)
                column.headerCell.alignment = spec.metric ? .right : .left; table.addTableColumn(column)
            }
            let header = NSMenu(); header.autoenablesItems = false; header.delegate = self
            for spec in owner.columns where spec.id != "name" {
                let item = NSMenuItem(title: spec.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.representedObject = spec.id; item.target = self
                item.state = table.tableColumns.first(where: { $0.identifier.rawValue == spec.id })?.isHidden == true ? .off : .on; header.addItem(item)
            }
            table.headerView?.menu = header
            let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
            for (name, action) in [("Properties", #selector(inspect)), ("Open file location", #selector(reveal)), ("Go to details", #selector(details)), ("Copy details", #selector(copyDetails))] {
                let item = NSMenuItem(title: name, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            table.menu = menu
            updateHeaders(force: true)
        }
        private func updateHeaders(force: Bool = false) {
            guard let table else { return }
            let descriptor = table.sortDescriptors.first
            let sortKey = descriptor?.key
            let ascending = descriptor?.ascending ?? true
            guard force || previousHeaderTotals != owner.headerTotals || previousHeaderSortKey != sortKey || previousHeaderSortAscending != ascending else { return }
            previousHeaderTotals = owner.headerTotals; previousHeaderSortKey = sortKey; previousHeaderSortAscending = ascending
            table.headerView?.frame.size.height = owner.headerTotals.isEmpty ? 28 : 52
            for column in table.tableColumns {
                guard let header = column.headerCell as? ResourceHeaderCell else { continue }
                header.total = owner.headerTotals[column.identifier.rawValue]
                header.tall = !owner.headerTotals.isEmpty
                header.resource = owner.columns.first { $0.id == column.identifier.rawValue }?.metric == true
                header.sortAscending = sortKey == column.identifier.rawValue ? ascending : nil
            }
            table.headerView?.needsDisplay = true
        }
        func reload() {
            guard let table else { return }
            updateHeaders()
            let descriptor = table.sortDescriptors.first
            let sortKey = descriptor?.key
            let ascending = descriptor?.ascending ?? true
            // Inventory pages receive every system snapshot, but their tables only
            // need work when their own data, expansion, or ordering has changed.
            guard previousRows != owner.rows || previousExpanded != expanded || previousSortKey != sortKey || previousSortAscending != ascending else { return }
            previousRows = owner.rows; previousExpanded = expanded
            previousSortKey = sortKey; previousSortAscending = ascending
            let selected = visible.indices.contains(table.selectedRow) ? visible[table.selectedRow].row.id : nil
            let sorted = owner.rows.sorted { lhs, rhs in
                let key = descriptor?.key ?? "name"
                if lhs.sortValues[key] != nil || rhs.sortValues[key] != nil {
                    let a = lhs.sortValues[key] ?? -1, b = rhs.sortValues[key] ?? -1
                    if a != b { return descriptor?.ascending == false ? a > b : a < b }
                }
                let a = lhs.values[key] ?? "", b = rhs.values[key] ?? ""
                let result = a.localizedStandardCompare(b)
                return descriptor?.ascending == false ? result == .orderedDescending : result == .orderedAscending
            }
            let next = sorted.flatMap { row in [VisibleRow(row: row, depth: 0)] + (expanded.contains(row.id) ? row.children.map { VisibleRow(row: $0, depth: 1) } : []) }
            let old = visible; visible = next
            if needsFullReload || old.map({ $0.row.id }) != next.map({ $0.row.id }) {
                table.reloadData(); needsFullReload = false
            } else {
                let changed = IndexSet(next.indices.filter { old[$0] != next[$0] })
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)) }
            }
            if let selected, let index = visible.firstIndex(where: { $0.row.id == selected }) {
                if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            } else { table.deselectAll(nil) }
            if icons.count > 2000 { icons.removeAll(keepingCapacity: true) }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { reload() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard visible.indices.contains(row), let column = tableColumn else { return nil }
            let entry = visible[row]; let id = column.identifier.rawValue
            let metric = owner.columns.first { $0.id == id }?.metric == true
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? AuxiliaryCell ?? AuxiliaryCell(nameColumn: id == "name", metric: metric, rightAligned: metric || id == "pid")
            cell.identifier = column.identifier
            let value = entry.row.values[id] ?? "—"
            cell.label.stringValue = value
            cell.metric = metric
            cell.toolTip = value == "—" ? "This counter is unavailable on macOS." : value
            if id == "name" {
                let hasChildren = !entry.row.children.isEmpty
                cell.labelLeading?.constant = CGFloat(entry.depth * 20 + (hasChildren ? 45 : 31))
                cell.iconLeading?.constant = CGFloat(entry.depth * 20 + (hasChildren ? 24 : 10))
                cell.disclosure.isHidden = !hasChildren
                cell.disclosure.identifier = .init(entry.row.id)
                cell.disclosure.target = self; cell.disclosure.action = #selector(toggleUser(_:))
                cell.disclosure.title = expanded.contains(entry.row.id) ? "▾" : "▸"
                cell.disclosure.setAccessibilityLabel("\(expanded.contains(entry.row.id) ? "Collapse" : "Expand") \(value)")
                if let path = entry.row.iconPath {
                    if icons[path] == nil { icons[path] = NSWorkspace.shared.icon(forFile: path) }
                    cell.icon.image = icons[path]; cell.icon.contentTintColor = nil
                } else {
                    let cacheKey = "symbol:\(entry.row.symbol)"
                    if icons[cacheKey] == nil { icons[cacheKey] = NSImage(systemSymbolName: entry.row.symbol, accessibilityDescription: nil) }
                    cell.icon.image = icons[cacheKey]; cell.icon.contentTintColor = .secondaryLabelColor
                }
            }
            cell.setAccessibilityLabel("\(column.title): \(value)")
            return cell
        }
        @objc func toggleUser(_ sender: NSButton) {
            guard let id = sender.identifier?.rawValue else { return }
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }; reload()
        }
        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let column = table?.tableColumns.first(where: { $0.identifier.rawValue == id }) else { return }
            column.isHidden.toggle(); sender.state = column.isHidden ? .off : .on
            UserDefaults.standard.set(column.isHidden, forKey: "secondaryColumn.\(signature).\(id)")
        }
        private var selected: AuxiliaryRow? { guard let table, visible.indices.contains(table.selectedRow) else { return nil }; return visible[table.selectedRow].row }
        func menuWillOpen(_ menu: NSMenu) {
            guard let table, menu === table.menu else { return }
            if visible.indices.contains(table.clickedRow) { table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false) }
            else { table.deselectAll(nil) }
            for item in menu.items {
                item.isEnabled = selected != nil
                if item.action == #selector(reveal) { item.isEnabled = selected?.path != nil }
                if item.action == #selector(details) { item.isEnabled = selected?.processID != nil && owner.onProcess != nil }
            }
        }
        @objc func openRow() {
            guard let row = selected else { return }
            if !row.children.isEmpty { if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }; reload() }
            else { inspect() }
        }
        @objc func inspect() {
            guard let row = selected else { return }
            let alert = NSAlert(); alert.messageText = row.values["name"] ?? "Properties"; alert.informativeText = detailText(row)
            alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Copy")
            if alert.runModal() == .alertSecondButtonReturn { copyDetails() }
        }
        @objc func reveal() { if let path = selected?.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
        @objc func details() { if let id = selected?.processID { owner.onProcess?(id) } }
        @objc func copyDetails() { if let row = selected { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(detailText(row), forType: .string) } }
        private func detailText(_ row: AuxiliaryRow) -> String { owner.columns.map { "\($0.title): \(row.values[$0.id] ?? "—")" }.joined(separator: "\n") + (row.path.map { "\nConfiguration: \($0)" } ?? "") }
    }
}

/// Reuse the label, icon, disclosure button and constraints as counters change.
private final class AuxiliaryCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()
    let disclosure = NSButton(title: "", target: nil, action: nil)
    var labelLeading: NSLayoutConstraint?
    var iconLeading: NSLayoutConstraint?
    var metric = false { didSet { if oldValue != metric { updateHeat() } } }
    init(nameColumn: Bool, metric: Bool, rightAligned: Bool) {
        self.metric = metric
        super.init(frame: .zero)
        label.font = metric ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11)
        label.alignment = rightAligned ? .right : .left
        label.lineBreakMode = .byTruncatingTail; label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        labelLeading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: nameColumn ? 31 : 9)
        NSLayoutConstraint.activate([labelLeading!, label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
        if nameColumn {
            icon.translatesAutoresizingMaskIntoConstraints = false; addSubview(icon)
            iconLeading = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
            NSLayoutConstraint.activate([iconLeading!, icon.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 15), icon.heightAnchor.constraint(equalToConstant: 15)])
            disclosure.isBordered = false; disclosure.translatesAutoresizingMaskIntoConstraints = false; disclosure.isHidden = true; addSubview(disclosure)
            NSLayoutConstraint.activate([disclosure.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), disclosure.centerYAnchor.constraint(equalTo: centerYAnchor), disclosure.widthAnchor.constraint(equalToConstant: 12)])
        }
        updateHeat()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateHeat() { wantsLayer = true; layer?.backgroundColor = metric ? NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor : nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateHeat() }
}

struct SettingsPage: View {
    @ObservedObject var store: MonitorStore
    @ViewState private var windowOptionsExpanded = true
    @ViewState private var otherOptionsExpanded = true
    @ViewState private var availabilityExpanded = false
    private var mac: Bool { store.appearance == .macOS }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsSection("Appearance") {
                    settingRow("App theme", detail: "Select which app theme to display", symbol: "paintpalette") {
                        StablePicker(title: "App theme", selection: $store.colorSchemeChoice, choices: [("Use system setting", "system"), ("Light", "light"), ("Dark", "dark")]).frame(width: 175)
                    }
                    settingRow("Interface style", detail: "Task Manager layout with your preferred system styling", symbol: "macwindow") {
                        StablePicker(title: "Interface style", selection: $store.appearance, choices: [("macOS · Liquid Glass", AppAppearance.macOS), ("Windows · Task Manager", AppAppearance.windows)]).frame(width: 175)
                    }
                }
                settingsSection("General") {
                    settingRow("Default start page", detail: "Specify which page is visible when launching Task Manager", symbol: "rectangle.split.2x2") {
                        StablePicker(title: "Default start page", selection: $store.defaultStartPage, choices: ManagerPage.allCases.filter { $0 != .settings }.map { ($0.title, $0) }).frame(width: 175)
                    }
                    settingRow("Real time update speed", detail: "Choose how often to update the system resource usage report", symbol: "speedometer") {
                        StablePicker(title: "Real time update speed", selection: Binding(get: { store.isPaused ? 0.0 : store.interval }, set: { value in
                            if value == 0 { if !store.isPaused { store.togglePause() } }
                            else { store.setInterval(value); if store.isPaused { store.togglePause() } }
                        }), choices: [("High · 0.5 seconds", 0.5), ("Normal · 1 second", 1.0), ("Low · 2 seconds", 2.0), ("Very low · 5 seconds", 5.0), ("Paused", 0.0)]).frame(width: 175)
                    }
                    settingRow("Graph time window", detail: "One fixed time scale for all Performance graphs, including logical CPUs and GPU memory", symbol: "clock") {
                        StablePicker(title: "Graph time window", selection: $store.graphWindow, choices: GraphTimeWindow.allCases.map { ($0.label, $0) }).frame(width: 175)
                    }
                    settingRow("CPU and GPU temperatures", detail: "Experimental sensor averages in °C; verified individual cores only. No polling while off.", symbol: "thermometer") {
                        Toggle("Show temperatures", isOn: $store.showTemperatures).toggleStyle(.checkbox)
                    }
                    VStack(spacing: 0) {
                        disclosureHeader("Window management", detail: "Specify default Task Manager window behavior", symbol: "macwindow.on.rectangle", expanded: $windowOptionsExpanded)
                        if windowOptionsExpanded {
                            Divider()
                            VStack(alignment: .leading, spacing: 15) {
                                Toggle("Always on top", isOn: $store.alwaysOnTop)
                                Toggle("Minimize on use", isOn: .constant(false)).disabled(true).help("This Windows window behavior is unavailable in this macOS version.")
                                Toggle("Hide when minimized", isOn: .constant(false)).disabled(true).help("macOS controls minimized windows through the Dock.")
                            }.toggleStyle(.checkbox).font(.system(size: 12)).padding(.leading, 48).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.background(cardBackground)
                    VStack(spacing: 0) {
                        disclosureHeader("Other options", detail: "Account names, history and confirmation dialog settings", symbol: "list.bullet", expanded: $otherOptionsExpanded)
                        if otherOptionsExpanded {
                            Divider()
                            VStack(alignment: .leading, spacing: 15) {
                                Toggle("Show full account name", isOn: .constant(false)).disabled(true).help("Users are identified by the local account name in this version.")
                                Toggle("Record history for accessible processes", isOn: Binding(get: { store.historyEnabled }, set: { store.setHistoryEnabled($0) }))
                                Toggle("Ask me before applying Efficiency mode", isOn: .constant(true)).disabled(true).help("Windows Efficiency mode is unavailable on macOS. CPU priority is available in the process menu.")
                            }.toggleStyle(.checkbox).font(.system(size: 12)).padding(.leading, 48).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.background(cardBackground)
                }
                settingsSection("Performance items") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose which resources appear in Performance. Choices survive app updates and remain saved for disconnected devices.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ForEach(store.performanceItems) { item in
                            Toggle(item.title, isOn: Binding(get: { store.performanceVisibility.isShown(item) }, set: { store.setPerformanceItem(item, shown: $0) }))
                        }
                        Button("Show all performance items") { store.showAllPerformanceItems() }
                    }.toggleStyle(.checkbox).font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground)
                }
                settingsSection("Local history") {
                    settingRow("Observed resource usage", detail: "Retain up to 30 days on this Mac", symbol: "clock.arrow.circlepath") {
                        Button("Delete usage history…") { store.clearHistory() }.disabled(store.historyRecords.isEmpty)
                    }
                    Text("History counts only observed intervals. Hidden or minimized windows refresh at most once every five seconds to reduce energy use.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
                VStack(spacing: 0) {
                    disclosureHeader("Metric availability", detail: "macOS counters and platform differences", symbol: "info.circle", expanded: $availabilityExpanded)
                    if availabilityExpanded {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CPU is reported as a share of this Mac's total capacity. P/E speed readings use experimental local IOReport counters and exclude idle time. Unsupported or unvalidated counters appear as a dash (—).")
                            Text("GPU activity and memory use are read from available local driver counters. Experimental per-process TCP/UDP rates use local native counters and remain unavailable when unsupported or inaccessible. Separate Windows GPU engines, Neural Engine utilization, startup impact, protected service controls and user disconnect are unavailable. Startup and services are read-only local inventories.")
                            Text("Task Manager runs with your permissions and does not install an administrator helper.")
                            ForEach(Array(Set(store.snapshot.warnings + store.inventory.warnings)).sorted(), id: \.self) { Text($0) }
                        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.background(cardBackground)
                VStack(alignment: .leading, spacing: 6) {
                    Text("About Task Manager").font(.system(size: 12, weight: .semibold))
                    Text("Built with Swift and Apple frameworks. Entirely local: no accounts, telemetry, remote assets, update checker or app-initiated network connections.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 4)
            }.frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 28).padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .windowBackgroundColor).opacity(mac ? 0.5 : 1))
    }
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: mac ? 10 : 4)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay { RoundedRectangle(cornerRadius: mac ? 10 : 4).strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1) }
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).padding(.bottom, 3)
            content()
        }
    }
    private func settingRow<Control: View>(_ title: String, detail: String, symbol: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 14)
            control().controlSize(.small)
        }.padding(.horizontal, 16).frame(minHeight: 59).background(cardBackground)
    }
    private func disclosureHeader(_ title: String, detail: String, symbol: String, expanded: Binding<Bool>) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).frame(minHeight: 59).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
    }
}
