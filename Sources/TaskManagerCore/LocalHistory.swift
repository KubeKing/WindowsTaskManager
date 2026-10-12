import Foundation

public struct AppHistoryRecord: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var cpuSeconds: Double
    public var readBytes: UInt64
    public var writeBytes: UInt64
    public var cpuAvailable: Bool
    public var readAvailable: Bool
    public var writeAvailable: Bool
    public var firstSeen: Date
    public var lastSeen: Date
    public init(id: String, name: String, cpuSeconds: Double = 0, readBytes: UInt64 = 0, writeBytes: UInt64 = 0, cpuAvailable: Bool = false, readAvailable: Bool = false, writeAvailable: Bool = false, firstSeen: Date, lastSeen: Date) {
        self.id = id; self.name = name; self.cpuSeconds = cpuSeconds; self.readBytes = readBytes; self.writeBytes = writeBytes
        self.cpuAvailable = cpuAvailable; self.readAvailable = readAvailable; self.writeAvailable = writeAvailable
        self.firstSeen = firstSeen; self.lastSeen = lastSeen
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, cpuSeconds, readBytes, writeBytes, cpuAvailable, readAvailable, writeAvailable, firstSeen, lastSeen
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        cpuSeconds = try values.decode(Double.self, forKey: .cpuSeconds)
        readBytes = try values.decode(UInt64.self, forKey: .readBytes); writeBytes = try values.decode(UInt64.self, forKey: .writeBytes)
        cpuAvailable = try values.decodeIfPresent(Bool.self, forKey: .cpuAvailable) ?? false
        readAvailable = try values.decodeIfPresent(Bool.self, forKey: .readAvailable) ?? false
        writeAvailable = try values.decodeIfPresent(Bool.self, forKey: .writeAvailable) ?? false
        firstSeen = try values.decode(Date.self, forKey: .firstSeen); lastSeen = try values.decode(Date.self, forKey: .lastSeen)
    }
}

/// Optional observed history. Call record only while collection is enabled.
/// Initial samples, process restarts and gaps over 60 seconds establish baselines;
/// activity outside those observed intervals is never charged to the history.
public final class LocalHistory {
    public private(set) var records: [AppHistoryRecord] = []
    public private(set) var observationStart: Date?
    public private(set) var lastError: String?
    private struct Day: Codable {
        var date: Date
        var records: [String: AppHistoryRecord]
    }
    private struct Archive: Codable {
        var version: Int = 1
        var observationStart: Date?
        var days: [Day]
    }
    private let fileURL: URL
    private var days: [Day] = []
    private var needsPersistence = false
    private var previous: [ProcessIdentity: ProcessRecord] = [:]
    private var previousDate: Date?
    private var previousMonotonic: Double?
    private let maximumApplications = 3000
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    public convenience init(directory: URL) { self.init(directory: directory, now: Date()) }
    init(directory: URL, now: Date) {
        fileURL = directory.appendingPathComponent("app-history.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let values = try fileURL.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            let size = values.fileSize ?? 0
            guard values.isRegularFile == true, size <= 20_000_000 else { throw HistoryError.invalidArchive }
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1, archive.days.count <= 31,
                  archive.days.allSatisfy({ day in
                      day.records.count <= maximumApplications && day.records.allSatisfy { key, record in
                          key == record.id && record.cpuSeconds.isFinite && record.cpuSeconds >= 0 && record.firstSeen <= record.lastSeen
                      }
                  }) else { throw HistoryError.invalidArchive }
            days = archive.days; observationStart = archive.observationStart
            prune(at: now); rebuildRecords()
        } catch { lastError = "Could not load local history: \(error.localizedDescription)" }
    }

    public func record(snapshot: SystemSnapshot) {
        let date = snapshot.timestamp
        guard date.timeIntervalSince1970.isFinite else { return }
        // A repeated/out-of-order snapshot must not replace the baseline and double-count later.
        if let priorDate = previousDate, date <= priorDate { return }
        prune(at: date)
        if observationStart == nil { observationStart = date }
        let elapsed = previousDate.map { date.timeIntervalSince($0) }
        let monotonicElapsed = previousMonotonic.flatMap { prior in snapshot.monotonicTime > 0 && prior > 0 ? snapshot.monotonicTime - prior : nil }
        let continuous = elapsed.map { $0 > 0 && $0 <= 60 } == true && (monotonicElapsed.map { $0 > 0 && $0 <= 60 } ?? true)
        let dayDate = Self.calendar.startOfDay(for: date)
        if !days.contains(where: { $0.date == dayDate }) { days.append(Day(date: dayDate, records: [:])) }
        guard let dayIndex = days.firstIndex(where: { $0.date == dayDate }) else { return }
        var current: [ProcessIdentity: ProcessRecord] = [:]
        for process in snapshot.processes {
            // A duplicate process row must never charge the same counters twice.
            guard current[process.id] == nil else { continue }
            current[process.id] = process
            let key = process.applicationPath ?? process.executablePath ?? "process:\(process.name)"
            if days[dayIndex].records[key] == nil && days[dayIndex].records.count >= maximumApplications { continue }
            let name = process.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? process.name
            var record = days[dayIndex].records[key] ?? AppHistoryRecord(id: key, name: name, firstSeen: date, lastSeen: date)
            if continuous, let prior = previous[process.id] {
                if let old = prior.totalCPUSeconds, let new = process.totalCPUSeconds, old.isFinite, new.isFinite, old >= 0, new >= old {
                    let sum = record.cpuSeconds + new - old
                    if sum.isFinite { record.cpuSeconds = sum; record.cpuAvailable = true }
                }
                if let delta = Self.delta(process.diskReadBytes, prior.diskReadBytes) {
                    record.readBytes = Self.add(record.readBytes, delta); record.readAvailable = true
                }
                if let delta = Self.delta(process.diskWriteBytes, prior.diskWriteBytes) {
                    record.writeBytes = Self.add(record.writeBytes, delta); record.writeAvailable = true
                }
            }
            record.lastSeen = date
            days[dayIndex].records[key] = record
        }
        previous = current; previousDate = date; previousMonotonic = snapshot.monotonicTime
        rebuildRecords(); needsPersistence = true
    }

    /// Prune and persist expired observations even when collection is disabled.
    /// An unchanged history does not touch the filesystem.
    public func maintain(at date: Date = Date()) throws {
        guard date.timeIntervalSince1970.isFinite else { return }
        prune(at: date); rebuildRecords()
        if needsPersistence { try save() }
    }

    /// Use when history is disabled or monitoring is paused, so resuming never charges a gap.
    public func resetBaseline() {
        previous = [:]; previousDate = nil; previousMonotonic = nil
    }

    public func clear() throws {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
            records = []; days = []; observationStart = nil; resetBaseline(); needsPersistence = false; lastError = nil
        } catch { lastError = "Could not clear local history: \(error.localizedDescription)"; throw error }
    }

    public func save() throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let archive = Archive(observationStart: observationStart, days: days)
            let data = try JSONEncoder().encode(archive)
            guard data.count <= 20_000_000 else { throw HistoryError.invalidArchive }
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            needsPersistence = false; lastError = nil
        } catch { lastError = "Could not save local history: \(error.localizedDescription)"; throw error }
    }

    private func prune(at date: Date) {
        let oldCount = days.count; let oldStart = observationStart
        let cutoff = Self.calendar.startOfDay(for: date).addingTimeInterval(-29 * 86400)
        days.removeAll { $0.date < cutoff || $0.date > Self.calendar.startOfDay(for: date) }
        if let start = observationStart, start < cutoff { observationStart = days.flatMap { $0.records.values }.map(\.firstSeen).min() }
        if oldCount != days.count || oldStart != observationStart { needsPersistence = true }
    }
    private func rebuildRecords() {
        var combined: [String: AppHistoryRecord] = [:]
        for day in days {
            for (key, record) in day.records {
                if var existing = combined[key] {
                    existing.cpuSeconds += record.cpuSeconds
                    existing.readBytes = Self.add(existing.readBytes, record.readBytes)
                    existing.writeBytes = Self.add(existing.writeBytes, record.writeBytes)
                    existing.cpuAvailable = existing.cpuAvailable || record.cpuAvailable
                    existing.readAvailable = existing.readAvailable || record.readAvailable
                    existing.writeAvailable = existing.writeAvailable || record.writeAvailable
                    existing.firstSeen = min(existing.firstSeen, record.firstSeen); existing.lastSeen = max(existing.lastSeen, record.lastSeen)
                    combined[key] = existing
                } else { combined[key] = record }
            }
        }
        records = combined.values.sorted { $0.lastSeen == $1.lastSeen ? $0.id < $1.id : $0.lastSeen > $1.lastSeen }
    }
    private static func delta(_ new: UInt64?, _ old: UInt64?) -> UInt64? {
        guard let new, let old, new >= old else { return nil }; return new - old
    }
    private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs); return overflow ? .max : sum
    }
    private enum HistoryError: LocalizedError {
        case invalidArchive
        var errorDescription: String? { "The history file is invalid or exceeds the storage limit." }
    }
}
