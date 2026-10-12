import Testing
import Foundation
import Darwin
@testable import TaskManagerCore

struct ProcessActionsTests {
    @Test func testRejectsPIDReuse() {
        let requested = ProcessIdentity(pid: 4321, startTime: 100)
        #expect(throws: ProcessActionError.self) { try ProcessActionPolicy.validate(requested: requested, current: .init(pid: 4321, startTime: 101), selfPID: 9999) }
    }

    @Test func testRejectsMissingProcess() {
        #expect(throws: ProcessActionError.self) { try ProcessActionPolicy.validate(requested: .init(pid: 4321, startTime: 100), current: nil, selfPID: 9999) }
    }

    @Test func testProtectsSelfAndSystemInit() {
        for pid: Int32 in [0, 1, 9999] {
            let id = ProcessIdentity(pid: pid, startTime: 100)
            #expect(throws: ProcessActionError.self) { try ProcessActionPolicy.validate(requested: id, current: id, selfPID: 9999) }
        }
    }

    @Test func testAcceptsMatchingIdentity() throws {
        let id = ProcessIdentity(pid: 4321, startTime: 100)
        try ProcessActionPolicy.validate(requested: id, current: id, selfPID: 9999)
    }

    @Test func testTerminatesOnlyExpendableChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let id = try #require(SystemSampler.identity(pid: child.processIdentifier))
        try ProcessActions.terminate(id, force: false)
        child.waitUntilExit()
        #expect(!child.isRunning)
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGTERM)
    }

    @Test func testForceQuitsOnlyExpendableChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let id = try #require(SystemSampler.identity(pid: child.processIdentifier))
        try ProcessActions.terminate(id, force: true)
        child.waitUntilExit()
        #expect(child.terminationStatus == SIGKILL)
    }
}
