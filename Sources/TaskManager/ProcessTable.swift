import AppKit
import SwiftUI
import TaskManagerCore

struct ProcessTable: NSViewRepresentable {
    @ObservedObject var store: MonitorStore
    var details: Bool
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.rowHeight = 28; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.style = .plain; table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.gridColor = NSColor.separatorColor.withAlphaComponent(0.2)
        table.target = context.coordinator; table.action = #selector(Coordinator.clicked); table.doubleAction = #selector(Coordinator.inspect)
        table.setAccessibilityLabel(details ? "Process details" : "Processes")
        context.coordinator.table = table
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        context.coordinator.configure(details: details)
        context.coordinator.installColumnMenu()
        let menu = NSMenu(); menu.autoenablesItems = false
        for (title, action) in [("Inspect process", #selector(Coordinator.inspect)), ("Quit", #selector(Coordinator.quit)), ("Force quit…", #selector(Coordinator.forceQuit)), ("Reveal executable", #selector(Coordinator.reveal)), ("Copy details", #selector(Coordinator.copyDetails))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = context.coordinator; menu.addItem(item)
        }
        let priorityItem = NSMenuItem(title: "CPU priority", action: nil, keyEquivalent: "")
        let priorityMenu = NSMenu(); priorityMenu.autoenablesItems = false
        for (title, nice) in [("Normal (0)", 0), ("Low (10)", 10), ("Lowest (19)", 19), ("High (−10)", -10)] {
            let item = NSMenuItem(title: title, action: #selector(Coordinator.priority(_:)), keyEquivalent: "")
            item.tag = nice; item.target = context.coordinator; priorityMenu.addItem(item)
        }
        priorityItem.submenu = priorityMenu; menu.addItem(.separator()); menu.addItem(priorityItem)
        menu.delegate = context.coordinator; table.menu = menu
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.store = store
        context.coordinator.configure(details: details)
        context.coordinator.update(records: store.visibleProcesses)
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var store: MonitorStore
        weak var table: NSTableView?
        var records: [ProcessRecord] = []
        enum Row: Equatable {
            case group(String, String, Int, [ProcessRecord])
            case process(ProcessRecord)
            var process: ProcessRecord? {
                switch self {
                case .process(let record): return record
                case .group(let key, _, _, let members):
                    guard !["applications", "background", "system"].contains(key) else { return nil }
                    let ids = Set(members.map { $0.id.pid })
                    let roots = members.filter { !ids.contains($0.parentPID) }
                    return (roots.isEmpty ? members : roots).min {
                        $0.id.startTime == $1.id.startTime ? $0.id.pid < $1.id.pid : $0.id.startTime < $1.id.startTime
                    }
                }
            }
            var identity: String { switch self { case .group(let id, _, _, _): return "group:" + id; case .process(let record): return "process:\(record.id.pid):\(record.id.startTime)" } }
        }
        var rows: [Row] = []
        var collapsed: Set<String> = []
        var initializedGroups: Set<String> = []
        var details: Bool? = nil
        var lastAppearance: AppAppearance?
        var columnMenu: NSMenu?
        var hiddenDetails: Set<String> = ["cpuTime", "threads", "started", "path"]
        var hiddenProcesses: Set<String> = []
        var icons: [String: NSImage] = [:]
        var childIDs: Set<ProcessIdentity> = []
        var updating = false
        var selectedRowIdentity: String?
        init(store: MonitorStore) { self.store = store }
        func configure(details: Bool) {
            guard let table, self.details != details else { return }
            self.details = details
            for column in table.tableColumns { table.removeTableColumn(column) }
            let columns: [(String, String, CGFloat)]
            if details {
                columns = [("name", "Name", 190), ("pid", "PID", 55), ("status", "Status", 80), ("user", "User name", 100), ("cpu", "CPU", 65), ("memory", "Memory", 95), ("architecture", "Architecture", 90), ("description", "Description", 200), ("cpuTime", "CPU time", 95), ("network", "Network", 95), ("threads", "Threads", 66), ("started", "Started", 125), ("path", "Executable path", 280)]
            } else {
                columns = [("name", "Name", 245), ("status", "Status", 90), ("cpu", "CPU", 70), ("memory", "Memory", 90), ("disk", "Disk", 85), ("network", "Network", 85)]
            }
            for (id, title, width) in columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = title
                column.headerCell = ResourceHeaderCell(textCell: title)
                column.width = width; column.minWidth = id == "name" ? 160 : 55
                column.maxWidth = id == "name" ? 900 : 350
                column.resizingMask = [.userResizingMask, .autoresizingMask]
                column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: id == "name" || id == "pid" || id == "user")
                if id != "name" && id != "user" && id != "path" { column.headerCell.alignment = .right }
                column.isHidden = (details ? hiddenDetails : hiddenProcesses).contains(id)
                table.addTableColumn(column)
            }
            if table.sortDescriptors.isEmpty { table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)] }
            table.headerView?.frame.size.height = details ? 28 : 52
            table.enclosingScrollView?.tile()
            updateHeaders()
            installColumnMenu()
            table.reloadData()
        }
        func installColumnMenu() {
            guard let table else { return }
            let menu = NSMenu(title: "Select columns"); menu.autoenablesItems = false; menu.delegate = self
            let explanation = NSMenuItem(title: "Select columns", action: nil, keyEquivalent: ""); explanation.isEnabled = false
            menu.addItem(explanation); menu.addItem(.separator())
            for column in table.tableColumns {
                let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = column.identifier.rawValue
                item.state = column.isHidden ? .off : .on
                item.isEnabled = column.identifier.rawValue != "name"
                menu.addItem(item)
            }
            columnMenu = menu; table.headerView?.menu = menu
            table.headerView?.toolTip = "Click to sort. Right-click to select columns. Drag column boundaries to resize."
        }
        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let key = sender.representedObject as? String, key != "name", let table,
                  let column = table.tableColumns.first(where: { $0.identifier.rawValue == key }) else { return }
            column.isHidden.toggle()
            if details == true {
                if column.isHidden { hiddenDetails.insert(key) } else { hiddenDetails.remove(key) }
            } else {
                if column.isHidden { hiddenProcesses.insert(key) } else { hiddenProcesses.remove(key) }
            }
            sender.state = column.isHidden ? .off : .on
            table.sizeLastColumnToFit(); table.enclosingScrollView?.tile()
            table.headerView?.needsDisplay = true
            table.needsDisplay = true
        }
        func sorted(_ values: [ProcessRecord]) -> [ProcessRecord] {
            let descriptor = table?.sortDescriptors.first ?? NSSortDescriptor(key: "name", ascending: true)
            return values.sorted { a, b in
                var comparison: ComparisonResult = .orderedSame
                switch descriptor.key {
                case "name": comparison = a.name.localizedStandardCompare(b.name)
                case "status": comparison = (a.status ?? "").localizedStandardCompare(b.status ?? "")
                case "cpuTime": comparison = compare(a.totalCPUSeconds, b.totalCPUSeconds)
                case "network": comparison = compare(a.networkBytesPerSecond, b.networkBytesPerSecond)
                case "user": comparison = a.user.localizedStandardCompare(b.user)
                case "description": comparison = descriptionFor(a).localizedStandardCompare(descriptionFor(b))
                case "architecture": comparison = a.name.localizedStandardCompare(b.name)
                case "path": comparison = (a.executablePath ?? "").localizedStandardCompare(b.executablePath ?? "")
                case "pid": comparison = compare(Double(a.id.pid), Double(b.id.pid))
                case "memory": comparison = compare(a.memoryBytes.map { Double($0) }, b.memoryBytes.map { Double($0) })
                case "disk": comparison = compare(diskRate(a), diskRate(b))
                case "threads": comparison = compare(a.threadCount.map { Double($0) }, b.threadCount.map { Double($0) })
                case "started": comparison = compare(Double(a.id.startTime), Double(b.id.startTime))
                default: comparison = compare(a.cpuPercent, b.cpuPercent)
                }
                if comparison == .orderedSame { return a.name == b.name ? a.id.pid < b.id.pid : a.name.localizedStandardCompare(b.name) == .orderedAscending }
                return descriptor.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
        private func sum(_ values: [Double?]) -> Double? {
            let available = values.compactMap { $0 }; return available.isEmpty ? nil : available.reduce(0, +)
        }
        private func groupPrecedes(_ lhs: [ProcessRecord], _ rhs: [ProcessRecord]) -> Bool {
            guard let a = lhs.first, let b = rhs.first else { return false }
            let descriptor = table?.sortDescriptors.first
            var result: ComparisonResult
            switch descriptor?.key {
            case "name":
                let an = a.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? a.name
                let bn = b.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? b.name
                result = an.localizedStandardCompare(bn)
            case "memory": result = compare(sum(lhs.map { $0.memoryBytes.map { Double($0) } }), sum(rhs.map { $0.memoryBytes.map { Double($0) } }))
            case "disk": result = compare(sum(lhs.map(diskRate)), sum(rhs.map(diskRate)))
            case "network": result = compare(sum(lhs.map(\.networkBytesPerSecond)), sum(rhs.map(\.networkBytesPerSecond)))
            case "pid": result = compare(Double(a.id.pid), Double(b.id.pid))
            default: result = compare(sum(lhs.map(\.cpuPercent)), sum(rhs.map(\.cpuPercent)))
            }
            if result == .orderedSame { return a.id.pid < b.id.pid }
            return descriptor?.ascending == true ? result == .orderedAscending : result == .orderedDescending
        }
        private func compare(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
            let a = lhs ?? -1, b = rhs ?? -1
            return a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }
        private func diskRate(_ record: ProcessRecord) -> Double? {
            guard let r = record.readBytesPerSecond, let w = record.writeBytesPerSecond else { return nil }; return r + w
        }
        func update(records values: [ProcessRecord]) {
            guard let table else { return }
            updating = true
            let next = sorted(values)
            let old = rows; records = next
            if details == true { rows = next.map(Row.process) }
            else {
                rows = []
                let apps = next.filter { $0.applicationPath != nil }
                let background = next.filter { $0.applicationPath == nil && $0.uid != 0 }
                let system = next.filter { $0.applicationPath == nil && $0.uid == 0 }
                childIDs = []
                var keys: [String] = []; var groups: [String: [ProcessRecord]] = [:]
                for process in apps {
                    let key = process.applicationPath!
                    if groups[key] == nil { keys.append(key) }
                    groups[key, default: []].append(process)
                }
                initializedGroups.formIntersection(keys)
                collapsed.formIntersection(Set(keys + ["applications", "background", "system"]))
                if !apps.isEmpty { rows.append(.group("applications", "Apps", keys.count, apps)) }
                for key in keys where groups[key]!.count > 1 && !initializedGroups.contains(key) {
                    collapsed.insert(key); initializedGroups.insert(key)
                }
                if !collapsed.contains("applications") {
                    for key in keys.sorted(by: { groupPrecedes(groups[$0]!, groups[$1]!) }) {
                        let children = groups[key]!
                        if children.count > 1 {
                            let name = URL(fileURLWithPath: key).deletingPathExtension().lastPathComponent
                            rows.append(.group(key, name, children.count, children))
                            if !collapsed.contains(key) { rows += children.map(Row.process); childIDs.formUnion(children.map(\.id)) }
                        } else { rows += children.map(Row.process) }
                    }
                }
                if !background.isEmpty { rows.append(.group("background", "Background processes", background.count, background)) }
                if !collapsed.contains("background") { rows += background.map(Row.process) }
                if !system.isEmpty { rows.append(.group("system", "System processes", system.count, system)) }
                if !collapsed.contains("system") { rows += system.map(Row.process) }
            }
            let identityChanged = old.map(\.identity) != rows.map(\.identity)
            let appearanceChanged = lastAppearance != store.appearance
            lastAppearance = store.appearance
            table.rowHeight = 28
            updateHeaders()
            if identityChanged || appearanceChanged { table.reloadData() }
            else {
                let changed = IndexSet(rows.indices.filter { old[$0] != rows[$0] })
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)) }
            }
            if let identity = store.selection {
                let preferred = rows.firstIndex { $0.identity == selectedRowIdentity && $0.process?.id == identity }
                if let row = preferred ?? rows.firstIndex(where: { $0.process?.id == identity }) {
                    selectedRowIdentity = rows[row].identity
                    if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
                } else { table.deselectAll(nil) }
            } else { selectedRowIdentity = nil; table.deselectAll(nil) }
            if icons.count > 2000 { icons.removeAll(keepingCapacity: true) }
            updating = false
        }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows.indices.contains(row) && rows[row].process != nil }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return 28 }
            if case .group(let key, _, _, _) = rows[row], ["applications", "background", "system"].contains(key) { return 34 }
            return 28
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard rows.indices.contains(row) else { return nil }
            let view = NSTableRowView()
            view.backgroundColor = .textBackgroundColor
            return view
        }
        @objc func toggleGroup(_ sender: NSButton) {
            guard let key = sender.identifier?.rawValue else { return }
            if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
            update(records: records)
        }
        @objc func clicked() {
            // The disclosure button owns expansion; selecting a group selects its parent process.
            return
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { update(records: records) }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            selectedRowIdentity = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].identity : nil
            store.selection = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].process?.id : nil
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let column = tableColumn else { return nil }
            let id = column.identifier.rawValue
            if case .group(let key, let name, let count, let members) = rows[row] {
                let section = ["applications", "background", "system"].contains(key)
                let cell = NSTableCellView()
                if id == "name" {
                    if section {
                        let label = NSTextField(labelWithString: "\(name) (\(count))")
                        label.font = .systemFont(ofSize: 14, weight: .regular)
                        label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label)
                        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                        label.toolTip = key == "system" ? "Processes owned by the system (root), excluding grouped applications" : nil
                    } else {
                        let button = NSButton(title: collapsed.contains(key) ? "›" : "⌄", target: self, action: #selector(toggleGroup(_:)))
                        button.identifier = NSUserInterfaceItemIdentifier(key); button.isBordered = false
                        button.font = .systemFont(ofSize: 15); button.contentTintColor = .secondaryLabelColor
                        let icon = NSImageView(); icon.image = iconFor(key); icon.imageScaling = .scaleProportionallyUpOrDown
                        let label = NSTextField(labelWithString: "\(name) (\(count))"); label.font = .systemFont(ofSize: 11)
                        label.lineBreakMode = .byTruncatingTail
                        for child in [button, icon, label] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
                        NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), button.widthAnchor.constraint(equalToConstant: 18), button.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 36), icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                        button.setAccessibilityLabel("\(collapsed.contains(key) ? "Expand" : "Collapse") \(name)")
                    }
                } else if !section {
                    var value = ""
                    if id == "cpu" { value = MetricFormat.percent(sum(members.map(\.cpuPercent))) }
                    else if id == "memory" { value = MetricFormat.bytes(sum(members.map { $0.memoryBytes.map { Double($0) } }).map { UInt64(max(0, $0)) }) }
                    else if id == "disk" { value = MetricFormat.rate(sum(members.map(diskRate))) }
                    else if id == "network" { value = MetricFormat.rate(sum(members.map(\.networkBytesPerSecond))) }
                    else if id == "status" { value = members.compactMap(\.status).contains("Running") ? "Running" : members.compactMap(\.status).first ?? "—" }
                    else { value = "—" }
                    let field = NSTextField(labelWithString: value)
                    field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); field.alignment = id == "status" ? .left : .right
                    field.textColor = .labelColor; field.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(field)
                    NSLayoutConstraint.activate([field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -9), field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                    if ["cpu", "memory", "disk", "network"].contains(id) {
                        cell.wantsLayer = true
                        let intensity = id == "cpu" ? min(0.3, (sum(members.map(\.cpuPercent)) ?? 0) / 100) : id == "memory" ? min(0.3, (sum(members.map { $0.memoryBytes.map { Double($0) } }) ?? 0) / max(1, Double(store.snapshot.memory.totalBytes))) : 0
                        cell.layer?.backgroundColor = (store.appearance == .windows ? NSColor.systemBlue : NSColor.controlAccentColor).withAlphaComponent(0.045 + intensity).cgColor
                    }
                    if id == "network" { cell.toolTip = store.snapshot.processNetworkNote }
                }
                return cell
            }
            guard let record = rows[row].process else { return nil }
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? ProcessCell ?? ProcessCell(nameColumn: id == "name")
            cell.identifier = column.identifier
            cell.label.alignment = ["name", "user", "path", "status", "architecture", "description"].contains(id) ? .left : .right
            cell.iconLeading?.constant = details == true ? 18 : childIDs.contains(record.id) ? 54 : 36
            cell.label.font = id == "name" ? NSFont.systemFont(ofSize: 11) : NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            var value: String; var intensity: Double = 0
            switch id {
            case "name": value = record.name
            case "pid": value = String(record.id.pid)
            case "status": value = record.status ?? "—"
            case "cpuTime": value = record.totalCPUSeconds.map { MetricFormat.uptime($0) } ?? "—"
            case "user": value = record.user.isEmpty ? "—" : record.user
            case "architecture": value = "—"
            case "description": value = descriptionFor(record)
            case "path": value = record.executablePath ?? "—"
            case "cpu": value = MetricFormat.percent(record.cpuPercent); intensity = min(0.8, (record.cpuPercent ?? 0) / 60)
            case "memory": value = MetricFormat.bytes(record.memoryBytes); intensity = min(0.7, Double(record.memoryBytes ?? 0) / max(1, Double(store.snapshot.memory.totalBytes)) * 3)
            case "disk": value = MetricFormat.rate(diskRate(record)); intensity = min(0.7, (diskRate(record) ?? 0) / 20_000_000)
            case "network": value = MetricFormat.rate(record.networkBytesPerSecond); intensity = min(0.7, (record.networkBytesPerSecond ?? 0) / 20_000_000)
            case "threads": value = record.threadCount.map(String.init) ?? "—"
            case "started": value = record.id.startTime == 0 ? "—" : Date(timeIntervalSince1970: Double(record.id.startTime) / 1_000_000).formatted(date: .omitted, time: .shortened)
            default: value = "—"
            }
            cell.label.stringValue = value
            cell.toolTip = id == "name" ? record.executablePath : value == "—" ? "Not available or permission restricted" : nil
            if id == "network" { cell.toolTip = "Receive: \(MetricFormat.rate(record.networkReceivedBytesPerSecond)) · Send: \(MetricFormat.rate(record.networkSentBytesPerSecond))\n" + store.snapshot.processNetworkNote }
            cell.heatColor = store.appearance == .windows ? .systemBlue : .controlAccentColor
            cell.heat = ["cpu", "memory", "disk", "network"].contains(id) ? 0.035 + intensity * 0.3 : 0
            if id == "name" {
                let path = record.applicationPath ?? record.executablePath
                if let path {
                    cell.icon.image = iconFor(path)
                } else { cell.icon.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Process") }
            }
            cell.setAccessibilityLabel("\(column.title): \(value)")
            return cell
        }
        private func descriptionFor(_ record: ProcessRecord) -> String {
            record.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? record.name
        }
        private func iconFor(_ path: String) -> NSImage? {
            if icons[path] == nil { icons[path] = NSWorkspace.shared.icon(forFile: path) }
            return icons[path]
        }
        private func updateHeaders() {
            guard let table else { return }
            for column in table.tableColumns {
                guard let header = column.headerCell as? ResourceHeaderCell else { continue }
                if details == true { header.total = nil }
                else {
                    switch column.identifier.rawValue {
                    case "cpu": header.total = store.snapshot.cpuUsage.map { String(format: "%.0f%%", $0) } ?? "—"
                    case "memory": header.total = store.snapshot.memory.usedPercent.map { String(format: "%.0f%%", $0) } ?? "—"
                    case "disk": header.total = MetricFormat.rate(store.totalDiskRate)
                    case "network": header.total = MetricFormat.rate(sum(store.snapshot.processes.map(\.networkBytesPerSecond)))
                    default: header.total = nil
                    }
                }
                column.headerToolTip = column.identifier.rawValue == "network" ? "Sum of observed accessible process TCP/UDP rates, including loopback. " + store.snapshot.processNetworkNote : nil
                header.tall = details != true
                header.resource = ["cpu", "memory", "disk", "network"].contains(column.identifier.rawValue)
                header.sortAscending = table.sortDescriptors.first?.key == column.identifier.rawValue ? table.sortDescriptors.first?.ascending : nil
            }
            table.headerView?.needsDisplay = true
        }
        func menuWillOpen(_ menu: NSMenu) {
            guard let table else { return }
            if menu === columnMenu {
                for item in menu.items {
                    guard let key = item.representedObject as? String, let column = table.tableColumns.first(where: { $0.identifier.rawValue == key }) else { continue }
                    item.state = column.isHidden ? .off : .on; item.isEnabled = key != "name"
                }
                return
            }
            if rows.indices.contains(table.clickedRow), rows[table.clickedRow].process != nil { table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false) } else { table.deselectAll(nil) }
            for item in menu.items {
                item.isEnabled = store.selectedProcess != nil
                if item.action == #selector(reveal) { item.isEnabled = store.selectedProcess?.executablePath != nil }
                if item.action == #selector(quit) || item.action == #selector(forceQuit) || item.submenu != nil {
                    item.isEnabled = store.canTerminateSelected
                    if !item.isEnabled { item.toolTip = "This process is protected or no process is selected." }
                }
            }
        }
        @objc func inspect() {
            if let table, table.clickedRow >= 0, rows.indices.contains(table.clickedRow), rows[table.clickedRow].process == nil { return }
            store.inspectSelected()
        }
        @objc func quit() { store.quitSelected(force: false) }
        @objc func forceQuit() { store.quitSelected(force: true) }
        @objc func reveal() { store.revealSelected() }
        @objc func copyDetails() { store.copySelected() }
        @objc func priority(_ sender: NSMenuItem) { store.changePriority(Int32(sender.tag)) }
    }
}

private final class ProcessCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()
    var iconLeading: NSLayoutConstraint?
    var heatColor: NSColor = .controlAccentColor { didSet { updateHeat() } }
    var heat: Double = 0 { didSet { updateHeat() } }
    private func updateHeat() {
        layer?.backgroundColor = heat > 0 ? heatColor.withAlphaComponent(heat).cgColor : NSColor.clear.cgColor
    }
    init(nameColumn: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label); textField = label
        if nameColumn {
            icon.translatesAutoresizingMaskIntoConstraints = false; icon.imageScaling = .scaleProportionallyUpOrDown; addSubview(icon)
            iconLeading = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36)
            NSLayoutConstraint.activate([iconLeading!, icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16), icon.centerYAnchor.constraint(equalTo: centerYAnchor), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7)])
        } else { label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true }
        NSLayoutConstraint.activate([label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateHeat() }
}

/// Totals share the native column geometry, so resizing and horizontal scrolling
/// keep them directly over their resource values, as in Windows Task Manager.
final class ResourceHeaderCell: NSTableHeaderCell {
    var total: String?
    var tall = true
    var resource = false
    var sortAscending: Bool?
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.textBackgroundColor.setFill(); cellFrame.fill()
        // AppKit also uses the last header cell to paint trailing filler. Its
        // custom resource total must only be drawn inside its actual column.
        guard let header = controlView as? NSTableHeaderView, let table = header.tableView,
              let index = table.tableColumns.firstIndex(where: { $0.headerCell === self }),
              !table.tableColumns[index].isHidden else { return }
        let columnFrame = header.headerRect(ofColumn: index).intersection(cellFrame)
        guard !columnFrame.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        columnFrame.clip()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = resource ? .right : .left
        paragraph.lineBreakMode = .byTruncatingTail
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        let inset: CGFloat = resource ? 9 : 15
        if let total, tall {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            NSAttributedString(string: total, attributes: attributes).draw(in: NSRect(x: cellFrame.minX + 6, y: cellFrame.minY + 8, width: cellFrame.width - 15, height: 18))
        }
        NSAttributedString(string: stringValue, attributes: labelAttributes).draw(in: NSRect(x: cellFrame.minX + (resource ? 5 : inset), y: cellFrame.minY + (tall ? 31 : 8), width: cellFrame.width - inset - 5, height: 15))
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: cellFrame.maxX - 0.5, y: cellFrame.minY, width: 0.5, height: cellFrame.height).fill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 0.5, width: cellFrame.width, height: 0.5).fill()
        if let sortAscending {
            let text = sortAscending ? "⌃" : "⌄"
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]).draw(at: NSPoint(x: cellFrame.midX - 4, y: cellFrame.minY + 1))
        }
    }
}
