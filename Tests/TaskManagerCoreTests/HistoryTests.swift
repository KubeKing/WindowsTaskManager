import Foundation
import Testing
@testable import TaskManagerCore

final class HistoryTests {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private var fixtures: [URL] = []
    deinit { for url in fixtures { try? FileManager.default.removeItem(at: url) } }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        fixtures.append(url)
        return url
    }
    private func sample(_ offset: Double, identity: ProcessIdentity = .init(pid: 42, startTime: 1), cpu: Double = 100, read: UInt64 = 1000, write: UInt64 = 500) -> SystemSnapshot {
        var process = ProcessRecord(id: identity, name: "Fixture")
        process.applicationPath = "/Applications/Fixture.app"
        process.totalCPUSeconds = cpu; process.diskReadBytes = read; process.diskWriteBytes = write
        var snapshot = SystemSnapshot(); snapshot.timestamp = origin.addingTimeInterval(offset); snapshot.monotonicTime = offset + 1; snapshot.processes = [process]
        return snapshot
    }

    @Test func testInitialSampleIsBaselineAndFurtherSamplesAccumulateOnlyDeltas() throws {
        let history = LocalHistory(directory: try directory())
        history.record(snapshot: sample(0))
        #expect(history.records.first?.cpuSeconds == 0)
        history.record(snapshot: sample(1, cpu: 102, read: 1500, write: 800))
        history.record(snapshot: sample(2, cpu: 103, read: 1800, write: 900))
        #expect(history.records.first?.cpuSeconds == 3)
        #expect(history.records.first?.readBytes == 800)
        #expect(history.records.first?.writeBytes == 400)
        #expect(history.observationStart == origin)
    }

    @Test func testPIDReuseDisappearanceAndLongGapsDoNotChargeUnobservedActivity() throws {
        let history = LocalHistory(directory: try directory())
        history.record(snapshot: sample(0))
        history.record(snapshot: sample(1, identity: .init(pid: 42, startTime: 2), cpu: 800))
        #expect(history.records.first?.cpuSeconds == 0)
        var absent = sample(2); absent.processes = []; history.record(snapshot: absent)
        history.record(snapshot: sample(3, identity: .init(pid: 42, startTime: 2), cpu: 900))
        history.record(snapshot: sample(100, identity: .init(pid: 42, startTime: 2), cpu: 1000))
        #expect(history.records.first?.cpuSeconds == 0)
        history.record(snapshot: sample(101, identity: .init(pid: 42, startTime: 2), cpu: 1001))
        #expect(history.records.first?.cpuSeconds == 1)
    }

    @Test func testRetentionPersistenceAndClear() throws {
        let url = try directory(); let history = LocalHistory(directory: url)
        history.record(snapshot: sample(0))
        history.record(snapshot: sample(1, cpu: 102))
        history.record(snapshot: sample(31 * 86400, cpu: 300))
        history.record(snapshot: sample(31 * 86400 + 1, cpu: 301))
        #expect(history.records.first?.cpuSeconds == 1)
        try history.save()
        let restored = LocalHistory(directory: url, now: origin.addingTimeInterval(31 * 86400 + 1))
        #expect(restored.records.first?.cpuSeconds == 1)
        // A newly launched collector establishes a new baseline.
        restored.record(snapshot: sample(31 * 86400 + 2, cpu: 10000))
        #expect(restored.records.first?.cpuSeconds == 1)
        try restored.clear()
        #expect(restored.records.isEmpty)
        #expect(restored.observationStart == nil)
        #expect(!(FileManager.default.fileExists(atPath: url.appendingPathComponent("app-history.json").path)))
    }

    @Test func testCorruptionIsToleratedAndReported() throws {
        let url = try directory()
        try Data("invalid history".utf8).write(to: url.appendingPathComponent("app-history.json"))
        let history = LocalHistory(directory: url)
        #expect(history.records.isEmpty)
        #expect(history.lastError != nil)
    }

    @Test func testMissingAndResetCountersDoNotUnderflow() throws {
        let history = LocalHistory(directory: try directory())
        history.record(snapshot: sample(0))
        history.record(snapshot: sample(1, cpu: 2, read: 2, write: 2))
        #expect(history.records.first?.cpuSeconds == 0)
        #expect(history.records.first?.readBytes == 0)
        history.record(snapshot: sample(2, cpu: 3, read: 5, write: 5))
        #expect(history.records.first?.readBytes == 3)
    }

    @Test func testMissingCountersAndDuplicateRowsAreNotCharged() throws {
        let history = LocalHistory(directory: try directory())
        var first = sample(0)
        first.processes[0].totalCPUSeconds = nil; first.processes[0].diskReadBytes = nil
        history.record(snapshot: first)
        var second = sample(1, cpu: 5, read: 5)
        second.processes += second.processes
        history.record(snapshot: second)
        #expect(history.records.first?.cpuSeconds == 0)
        #expect(history.records.first?.readBytes == 0)
        history.record(snapshot: sample(2, cpu: 6, read: 7))
        #expect(history.records.first?.cpuSeconds == 1)
        #expect(history.records.first?.readBytes == 2)
        // Replaying an old snapshot cannot replace the latest baseline.
        history.record(snapshot: sample(1, cpu: 5, read: 5))
        history.record(snapshot: sample(3, cpu: 7, read: 9))
        #expect(history.records.first?.cpuSeconds == 2)
        #expect(history.records.first?.readBytes == 4)
    }

    @Test func testProcessesInOneApplicationAggregateAndPauseResetsBaseline() throws {
        let history = LocalHistory(directory: try directory())
        var first = sample(0)
        var secondProcess = first.processes[0]
        secondProcess.id = .init(pid: 43, startTime: 2)
        first.processes.append(secondProcess)
        history.record(snapshot: first)
        var second = first; second.timestamp = origin.addingTimeInterval(1); second.monotonicTime = 2
        second.processes[0].totalCPUSeconds = 101; second.processes[1].totalCPUSeconds = 102
        history.record(snapshot: second)
        #expect(history.records.count == 1)
        #expect(history.records.first?.cpuSeconds == 3)
        history.resetBaseline()
        history.record(snapshot: sample(2, cpu: 800))
        #expect(history.records.first?.cpuSeconds == 3)
    }

    @Test func testObservedZeroCountersAreAvailableAndNeverObservedCountersAreUnknown() throws {
        let history = LocalHistory(directory: try directory())
        history.record(snapshot: sample(0))
        #expect(history.records.first?.cpuAvailable == false)
        #expect(history.records.first?.readAvailable == false)
        #expect(history.records.first?.writeAvailable == false)
        history.record(snapshot: sample(1))
        #expect(history.records.first?.cpuSeconds == 0)
        #expect(history.records.first?.cpuAvailable == true)
        #expect(history.records.first?.readAvailable == true)
        #expect(history.records.first?.writeAvailable == true)
        var unavailable = sample(2, identity: .init(pid: 55, startTime: 3))
        unavailable.processes[0].applicationPath = "/Applications/Unavailable.app"
        unavailable.processes[0].totalCPUSeconds = nil
        unavailable.processes[0].diskReadBytes = nil
        unavailable.processes[0].diskWriteBytes = nil
        history.record(snapshot: unavailable)
        unavailable.timestamp = origin.addingTimeInterval(3); unavailable.monotonicTime = 4
        history.record(snapshot: unavailable)
        let record = try #require(history.records.first { $0.name == "Unavailable" })
        #expect(!record.cpuAvailable && !record.readAvailable && !record.writeAvailable)
    }

    @Test func testLegacyRecordsDecodeUnavailableFlagsAsFalse() throws {
        let record = AppHistoryRecord(id: "legacy", name: "Legacy", firstSeen: origin, lastSeen: origin)
        let data = try JSONEncoder().encode(record)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "cpuAvailable"); object.removeValue(forKey: "readAvailable"); object.removeValue(forKey: "writeAvailable")
        let legacy = try JSONDecoder().decode(AppHistoryRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!legacy.cpuAvailable && !legacy.readAvailable && !legacy.writeAvailable)
    }

    @Test func testMaintenancePersistsExpiryEvenWithoutRecording() throws {
        let url = try directory(); let original = LocalHistory(directory: url)
        original.record(snapshot: sample(0)); original.record(snapshot: sample(1)); try original.save()
        let file = url.appendingPathComponent("app-history.json")
        let oldData = try Data(contentsOf: file)
        let now = origin.addingTimeInterval(31 * 86400)
        let restored = LocalHistory(directory: url, now: now)
        #expect(restored.records.isEmpty)
        #expect(try Data(contentsOf: file) == oldData)
        try restored.maintain(at: now)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let days = try #require(object["days"] as? [Any])
        #expect(days.isEmpty)
        let expiredData = try Data(contentsOf: file)
        try restored.maintain(at: now.addingTimeInterval(60))
        #expect(try Data(contentsOf: file) == expiredData)
        #expect(restored.observationStart == nil)
        // The same maintenance also expires history in a long-running disabled instance.
        #expect(original.records.count == 1)
        try original.maintain(at: now)
        #expect(original.records.isEmpty)
    }

    @Test func testDailyAggregationKeepsEarlierObservedAvailability() throws {
        let history = LocalHistory(directory: try directory())
        history.record(snapshot: sample(0)); history.record(snapshot: sample(1))
        // The next day's initial sample has no continuous delta; the previous day's
        // actual zero observation remains available when the daily records combine.
        history.record(snapshot: sample(86400))
        #expect(history.records.first?.cpuAvailable == true)
        #expect(history.records.first?.readAvailable == true)
        #expect(history.records.first?.writeAvailable == true)
    }

}
