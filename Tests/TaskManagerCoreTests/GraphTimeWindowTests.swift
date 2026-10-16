import Foundation
import Testing
@testable import TaskManagerCore

struct GraphTimeWindowTests {
    @Test func positionsKeepTheSameScaleAsHistoryFillsAndCadenceChanges() {
        let end = Date(timeIntervalSince1970: 1000)
        let timeline = GraphTimeline(end:end,window:.oneMinute)
        #expect(timeline.position(end) == 1)
        #expect(timeline.position(end.addingTimeInterval(-30)) == 0.5)
        #expect(timeline.position(end.addingTimeInterval(-60)) == 0)
        for cadence in [0.5,1,2,5] {
            let points = stride(from: 0.0, through: 300, by:cadence).map { age -> HistoryPoint in
                var snapshot = SystemSnapshot(); snapshot.timestamp = end.addingTimeInterval(-300+age)
                return HistoryPoint(snapshot:snapshot)
            }
            let visible = GraphHistory.visible(points,seconds:60)
            #expect(visible.last?.timestamp == end)
            #expect(visible.first!.timestamp <= end.addingTimeInterval(-60))
            #expect(timeline.position(end.addingTimeInterval(-30)) == 0.5)
        }
    }
    @Test func oldPointsScrollLeftWithoutChangingDuration() {
        let first = Date(timeIntervalSince1970:1000)
        let before = GraphTimeline(end:first,window:.twoMinutes)
        let after = GraphTimeline(end:first.addingTimeInterval(30),window:.twoMinutes)
        #expect(before.position(first.addingTimeInterval(-60)) == 0.5)
        #expect(after.position(first.addingTimeInterval(-60)) == 0.25)
        #expect(before.seconds == after.seconds)
        #expect(GraphTimeline(end:first,window:.oneMinute).position(Date(timeIntervalSince1970:.nan)) == nil)
    }
    @Test func retentionUsesElapsedTimeAndHasAHardBound() {
        let points = (0..<2000).map { index -> HistoryPoint in
            var snapshot=SystemSnapshot();snapshot.timestamp=Date(timeIntervalSince1970:Double(index))
            return HistoryPoint(snapshot:snapshot)
        }
        let retained=GraphHistory.retained(points)
        #expect(retained.count == 602)
        #expect(retained.first?.timestamp == Date(timeIntervalSince1970:1398))
        let burst=points.map { point -> HistoryPoint in var p=point;p.timestamp=Date(timeIntervalSince1970:2000);return p }
        #expect(GraphHistory.retained(burst).count == GraphHistory.maximumPoints)
    }
    @Test func windowPreferencesPersistAndInvalidValuesFallBack() {
        let name="graph-window-tests-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        #expect(GraphTimeWindow.load(defaults) == .oneMinute)
        GraphTimeWindow.fiveMinutes.save(defaults)
        #expect(GraphTimeWindow.load(defaults) == .fiveMinutes)
        defaults.set(99999,forKey:"graphTimeWindow.v1")
        #expect(GraphTimeWindow.load(defaults) == .oneMinute)
    }
}
