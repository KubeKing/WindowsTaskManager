import Foundation
import Testing
@testable import TaskManagerCore

struct ProcessQueryTests {
    @Test func whitespaceReturnsAllRecords() {
        let records = [ProcessRecord(id: .init(pid: 10, startTime: 1), name: "Safari")]
        #expect(ProcessQuery.filter(records, query: " \n\t") == records)
    }
    @Test func searchMatchesAllTermsAcrossFields() {
        var safari = ProcessRecord(id: .init(pid: 10, startTime: 1), name: "Safari")
        safari.user = "taylor"; safari.executablePath = "/Applications/Safari.app/Contents/MacOS/Safari"
        let helper = ProcessRecord(id: .init(pid: 11, startTime: 1), name: "Safari Helper")
        #expect(ProcessQuery.filter([safari, helper], query: "SAFARI 10") == [safari])
        #expect(ProcessQuery.filter([safari, helper], query: "taylor Applications") == [safari])
        #expect(ProcessQuery.filter([safari, helper], query: "does-not-exist").isEmpty)
    }
}
