import AppKit
import SwiftUI
import TaskManagerCore

struct RootView: View {
    @ObservedObject var store: MonitorStore
    @ViewState private var sidebarCollapsed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    private var mac: Bool { store.appearance == .macOS }
    private var sidebarWidth: CGFloat { sidebarCollapsed ? 48 : 220 }
    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    commandBar
                    Divider()
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: mac ? 10 : 7))
                .overlay(alignment: .leading) { Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.4)).frame(width: 0.5) }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(store.colorSchemeChoice == "dark" ? .dark : store.colorSchemeChoice == "light" ? .light : nil)
        .alert("Task Manager", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    private var titleStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { sidebarCollapsed.toggle() } label: {
                    Image(systemName: "line.3.horizontal").font(.system(size: 15, weight: .regular)).frame(width: 32, height: 30)
                }.buttonStyle(.plain).help(sidebarCollapsed ? "Expand navigation" : "Collapse navigation").accessibilityLabel(sidebarCollapsed ? "Expand navigation" : "Collapse navigation")
                Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 14)).foregroundStyle(.blue)
                Text("Task Manager").font(.system(size: 12))
            }.padding(.leading, 8).frame(width: 220, alignment: .leading)
            Spacer(minLength: 10)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search by name, user or PID", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 11)).accessibilityLabel("Search processes and local inventories")
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9).frame(width: 295, height: 25)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25), in: RoundedRectangle(cornerRadius: mac ? 7 : 3))
            Spacer(minLength: 10)
            Picker("Appearance", selection: $store.appearance) {
                Text("macOS").tag(AppAppearance.macOS)
                Text("Windows").tag(AppAppearance.windows)
            }.labelsHidden().pickerStyle(.segmented).controlSize(.mini).frame(width: 139).padding(.trailing, 14)
        }.frame(height: 38)
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                ForEach(ManagerPage.allCases.filter { $0 != .settings }) { page in sidebarButton(page) }
            }.padding(.top, 2)
            Spacer(minLength: 0)
            sidebarButton(.settings).padding(.bottom, 4)
        }
        .frame(width: sidebarWidth)
        .background {
            if mac && !reduceTransparency { GlassBackground().glassEffect(.regular, in: .rect(cornerRadius: 0)) }
            else { Color(nsColor: .windowBackgroundColor) }
        }
    }
    private func sidebarButton(_ page: ManagerPage) -> some View {
        Button { store.page = page } label: {
            HStack(spacing: 14) {
                Image(systemName: page.symbol).font(.system(size: 14, weight: .regular)).frame(width: 20)
                if !sidebarCollapsed { Text(page.title).font(.system(size: 12)); Spacer(minLength: 0) }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, sidebarCollapsed ? 10 : 14).frame(height: 37)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if store.page == page {
                    RoundedRectangle(cornerRadius: mac ? 8 : 4).fill(Color.accentColor.opacity(scheme == .dark ? 0.21 : 0.07))
                        .overlay(alignment: .leading) { Capsule().fill(Color.accentColor).frame(width: 3, height: 17) }
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 4)
        .help(page.title).accessibilityLabel(page.title).accessibilityAddTraits(store.page == page ? .isSelected : [])
    }
    private var commandBar: some View {
        HStack(spacing: 10) {
            Text(store.page.title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            if store.page != .settings {
                Button { store.launchApplication() } label: { Label("Run new task", systemImage: "square.badge.plus") }
                    .buttonStyle(.plain).font(.system(size: 11))
                if store.page == .processes || store.page == .details {
                    commandDivider
                    Button { store.quitSelected(force: false) } label: { Label("End task", systemImage: "nosign") }
                        .buttonStyle(.plain).font(.system(size: 11)).disabled(!store.canTerminateSelected)
                        .help(store.canTerminateSelected ? "Quit selected process" : "Select a process that can be safely terminated")
                }
                if store.page == .processes {
                    commandDivider
                    Button {} label: { Label("Efficiency mode", systemImage: "leaf") }
                        .buttonStyle(.plain).font(.system(size: 11)).disabled(true)
                        .help("Windows Efficiency mode has no supported macOS counterpart. CPU priority is available in View and the process context menu.")
                        .accessibilityHint("Unavailable on macOS. Use CPU priority from the View menu.")
                }
                if store.page == .details {
                    commandDivider
                    Button { store.inspectSelected() } label: { Label("Properties", systemImage: "doc.text.magnifyingglass") }
                        .buttonStyle(.plain).font(.system(size: 11)).disabled(store.selectedProcess == nil)
                }
                if store.page == .startup {
                    commandDivider
                    unsupportedCommand("Enable", symbol: "checkmark.circle", reason: "macOS does not provide a public API to enable another app's login items. Use Open Login Items.")
                    unsupportedCommand("Disable", symbol: "nosign", reason: "macOS does not provide a public API to disable another app's login items. Use Open Login Items.")
                    commandDivider
                    Button("Open Login Items…") { store.openLoginItems() }.buttonStyle(.plain).font(.system(size: 11))
                }
                if store.page == .users {
                    commandDivider
                    unsupportedCommand("Disconnect", symbol: "person.crop.circle.badge.xmark", reason: "Disconnecting another macOS user's session is unavailable without a separately authorized administrative helper.")
                    Button("Manage user accounts") { openUserAccounts() }.buttonStyle(.plain).font(.system(size: 11))
                }
                if store.page == .services {
                    commandDivider
                    unsupportedCommand("Start", symbol: "play", reason: "Starting launchd services is unavailable in this read-only inventory.")
                    unsupportedCommand("Stop", symbol: "stop", reason: "Stopping launchd services is unavailable in this read-only inventory.")
                    unsupportedCommand("Restart", symbol: "arrow.clockwise", reason: "Restarting launchd services is unavailable in this read-only inventory.")
                }
            }
            commandDivider
            viewMenu
        }.padding(.horizontal, 16).frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor).opacity(mac ? 0.28 : 0.42))
    }
    private func unsupportedCommand(_ title: String, symbol: String, reason: String) -> some View {
        Button {} label: { Label(title, systemImage: symbol) }
            .buttonStyle(.plain).font(.system(size: 10)).disabled(true).help(reason).accessibilityHint(reason)
    }
    private func openUserAccounts() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"), NSWorkspace.shared.open(url) else {
            store.errorMessage = "Could not open Users & Groups. Open System Settings to manage user accounts."
            return
        }
    }
    private var commandDivider: some View { Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.35)).frame(width: 0.5, height: 24) }
    private var viewMenu: some View {
        HStack(spacing: 4) {
            if store.isPaused { Image(systemName: "pause.circle").foregroundStyle(.orange) }
            MoreMenu(store: store).frame(width: 26, height: 24)
        }
    }
    @ViewBuilder private var content: some View {
        switch store.page {
        case .processes, .details:
            ZStack {
                ProcessTable(store: store, details: store.page == .details)
                if store.visibleProcesses.isEmpty { ContentUnavailableView.search(text: store.query).allowsHitTesting(false) }
            }
        case .performance: PerformanceView(store: store)
        case .settings: SettingsPage(store: store)
        case .appHistory: HistoryPage(store: store)
        case .startup: InventoryPage(store: store, kind: .startup)
        case .users: InventoryPage(store: store, kind: .users)
        case .services: InventoryPage(store: store, kind: .services)
        }
    }
}
