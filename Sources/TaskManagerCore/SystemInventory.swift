import Foundation
import Darwin

public struct InventoryEntry: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var state: String
    public var path: String?
    public var owner: String?
    public var kind: String
    public init(id: String, name: String, detail: String, state: String, path: String? = nil, owner: String? = nil, kind: String) {
        self.id = id; self.name = name; self.detail = detail; self.state = state
        self.path = path; self.owner = owner; self.kind = kind
    }
}

public struct InventorySnapshot: Sendable {
    public var startup: [InventoryEntry]
    public var services: [InventoryEntry]
    public var sessions: [InventoryEntry]
    public var warnings: [String]
    public init(startup: [InventoryEntry] = [], services: [InventoryEntry] = [], sessions: [InventoryEntry] = [], warnings: [String] = []) {
        self.startup = startup; self.services = services; self.sessions = sessions; self.warnings = warnings
    }
}

/// Read-only local inventory. A configured plist does not prove a job is loaded.
public struct SystemInventory {
    private static let sessionLock = NSLock()
    public init() {}

    public func scan() -> InventorySnapshot {
        var result = InventorySnapshot()
        let loadedResult = Self.loadedJobs()
        let loaded = loadedResult.jobs
        if let warning = loadedResult.warning { result.warnings.append(warning) }
        let userAgents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        for directory in [userAgents, URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/System/Library/LaunchAgents")] {
            let scan = Self.launchEntries(in: directory, kind: "Launch agent", loaded: loaded)
            result.startup += scan.entries; result.warnings += scan.warnings
        }
        for path in ["/Library/LaunchDaemons", "/System/Library/LaunchDaemons"] {
            let scan = Self.launchEntries(in: URL(fileURLWithPath: path), kind: "Launch daemon", loaded: [:])
            result.services += scan.entries; result.warnings += scan.warnings
        }
        result.services = Self.serviceEntries(startup: result.startup, daemons: result.services, loaded: loaded)
        result.sessions = Self.loginSessions()
        result.startup.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.services.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.warnings.append("Startup lists configured launch agents. macOS does not provide a public API to enumerate every app's Login Items; use System Settings for that list.")
        result.warnings.append("Loaded states cover the current user's launch domain. System daemon runtime state is unknown; plist Disabled values may be overridden by launchd.")
        if result.sessions.isEmpty { result.warnings.append("No login sessions were reported by the local utmpx database.") }
        return result
    }

    static func serviceEntries(startup: [InventoryEntry], daemons: [InventoryEntry], loaded: [String: String]) -> [InventoryEntry] {
        let configured = startup + daemons
        let labels = Set(configured.map(\.name))
        let runtime = loaded.filter { !labels.contains($0.key) }.map { label, state in
            InventoryEntry(id: "loaded:\(label)", name: label, detail: "Loaded in the current user's launch domain", state: state, owner: NSUserName(), kind: "Loaded user job")
        }
        var ids = Set<String>()
        return (configured + runtime).filter { ids.insert($0.id).inserted }
    }

    static func launchEntries(in directory: URL, kind: String, loaded: [String: String]) -> (entries: [InventoryEntry], warnings: [String]) {
        var entries: [InventoryEntry] = []; var warnings: [String] = []
        guard FileManager.default.fileExists(atPath: directory.path) else { return (entries, warnings) }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            for file in files.filter({ $0.pathExtension == "plist" }).sorted(by: { $0.path < $1.path }) {
                do {
                    let values = try file.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true else { warnings.append("Skipped non-file launch plist: \(file.lastPathComponent)"); continue }
                    let size = values.fileSize ?? 0
                    guard size <= 2_000_000 else { warnings.append("Skipped oversized launch plist: \(file.lastPathComponent)"); continue }
                    let data = try Data(contentsOf: file)
                    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                          let label = plist["Label"] as? String, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        warnings.append("Invalid launch plist or missing Label: \(file.lastPathComponent)"); continue
                    }
                    let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                    let disabled = (plist["Disabled"] as? Bool) == true
                    let state = loaded[label] ?? (disabled ? "Configured · disabled in plist" : "Configured · load state unknown")
                    let owner = kind == "Launch agent" ? NSUserName() : ((plist["UserName"] as? String) ?? "root")
                    entries.append(InventoryEntry(id: file.path, name: label, detail: program ?? "Executable not specified", state: state, path: file.path, owner: owner, kind: kind))
                } catch { warnings.append("Cannot read \(file.lastPathComponent): \(error.localizedDescription)") }
            }
        } catch { warnings.append("Cannot read \(directory.path): \(error.localizedDescription)") }
        return (entries, warnings)
    }

    static func parseLaunchctl(_ output: String) -> [String: String] {
        var jobs: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let columns = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard columns.count == 3, Int(columns[1]) != nil else { continue }
            if columns[0] == "-" { jobs[String(columns[2])] = "Loaded · idle" }
            else if let pid = Int32(columns[0]), pid > 0 { jobs[String(columns[2])] = "Running · PID \(pid)" }
        }
        return jobs
    }

    private static func loadedJobs() -> (jobs: [String: String], warning: String?) {
        // A file avoids pipe-buffer deadlocks while the child is running. No shell or network.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("task-manager-launchctl-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            return ([:], "Could not create temporary output for launchctl.")
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/launchctl"); task.arguments = ["list"]
            task.standardOutput = output; task.standardError = output
            try task.run()
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while task.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if task.isRunning {
                task.terminate()
                let grace = ProcessInfo.processInfo.systemUptime + 0.3
                while task.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.02) }
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                return ([:], "launchctl timed out; loaded job states are unavailable.")
            }
            guard task.terminationStatus == 0 else { return ([:], "launchctl could not read the current user's jobs.") }
            let input = try FileHandle(forReadingFrom: outputURL)
            defer { try? input.close() }
            let data = try input.read(upToCount: 1_048_576) ?? Data()
            return (parseLaunchctl(String(decoding: data, as: UTF8.self)), data.count == 1_048_576 ? "Loaded jobs output was truncated to 1 MiB." : nil)
        } catch { return ([:], "Loaded jobs unavailable: \(error.localizedDescription)") }
    }

    private static func loginSessions() -> [InventoryEntry] {
        sessionLock.lock(); defer { sessionLock.unlock() }
        setutxent(); defer { endutxent() }
        var sessions: [InventoryEntry] = []
        while let pointer = getutxent() {
            var entry = pointer.pointee
            guard entry.ut_type == USER_PROCESS else { continue }
            let user = withUnsafeBytes(of: &entry.ut_user) { bytes in String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self) }
            let terminal = withUnsafeBytes(of: &entry.ut_line) { bytes in String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self) }
            let host = withUnsafeBytes(of: &entry.ut_host) { bytes in String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self) }
            guard !user.isEmpty else { continue }
            sessions.append(InventoryEntry(id: "session:\(entry.ut_pid):\(terminal)", name: user, detail: host.isEmpty ? terminal : "\(terminal) · \(host)", state: "Logged in", owner: user, kind: "Login session"))
        }
        return sessions
    }
}
