import Foundation
import Testing
@testable import TaskManagerCore

final class InventoryTests {
    private var fixtures: [URL] = []
    deinit { for url in fixtures { try? FileManager.default.removeItem(at: url) } }
    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        fixtures.append(url)
        return url
    }

    @Test func testMalformedAndMissingLabelsAreReportedWithoutInventingEntries() throws {
        let directory = try fixtureDirectory()
        try Data("not a plist".utf8).write(to: directory.appendingPathComponent("bad.plist"))
        let data = try PropertyListSerialization.data(fromPropertyList: ["Program": "/bin/test"], format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("unlabelled.plist"))
        let result = SystemInventory.launchEntries(in: directory, kind: "Launch agent", loaded: [:])
        #expect(result.entries.isEmpty)
        #expect(result.warnings.count == 2)
    }

    @Test func testConfiguredAndLoadedJobsHaveDifferentStates() throws {
        let directory = try fixtureDirectory()
        for label in ["test.running", "test.loaded", "test.configured", "test.disabled"] {
            let plist: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/sleep", "10"], "Disabled": label == "test.disabled"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
                .write(to: directory.appendingPathComponent(label + ".plist"))
        }
        let result = SystemInventory.launchEntries(in: directory, kind: "Launch agent", loaded: ["test.running": "Running · PID 42", "test.loaded": "Loaded · idle"])
        #expect(result.entries.count == 4)
        let states = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.name, $0.state) })
        #expect(states["test.running"] == "Running · PID 42")
        #expect(states["test.loaded"] == "Loaded · idle")
        #expect(states["test.configured"] == "Configured · load state unknown")
        #expect(states["test.disabled"] == "Configured · disabled in plist")
        #expect(result.entries.allSatisfy { $0.detail == "/bin/sleep" })
    }

    @Test func testLaunchctlParserIgnoresHeaderAndMalformedRows() {
        let jobs = SystemInventory.parseLaunchctl("PID\tStatus\tLabel\n42\t0\ttest.running\n-\t0\ttest.idle\nbad\t0\ttest.bad\n")
        #expect(jobs == ["test.running": "Running · PID 42", "test.idle": "Loaded · idle"])
    }
    @Test func testServicesIncludeAgentsAndDaemonsAndDeduplicateConfiguredJobs() {
        let agent = InventoryEntry(id: "/agent.plist", name: "agent", detail: "agent", state: "Configured", kind: "Launch agent")
        let daemon = InventoryEntry(id: "/daemon.plist", name: "daemon", detail: "daemon", state: "Configured", kind: "Launch daemon")
        let entries = SystemInventory.serviceEntries(startup: [agent, agent], daemons: [daemon], loaded: ["agent": "Loaded · idle", "runtime": "Loaded · idle"])
        #expect(entries.count == 3)
        #expect(entries.first { $0.id == agent.id }?.state == "Configured")
        #expect(entries.contains { $0.id == daemon.id })
        #expect(entries.contains { $0.name == "runtime" && $0.state == "Loaded · idle" })
    }

}
