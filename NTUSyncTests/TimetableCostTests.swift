import Testing
import Foundation
@testable import NTUSync

struct TimetableCostTests {

    static func loadTimetable() throws -> ShuttleTimetable {
        try ShuttleTimetable.loadBundled()
    }

    @Test func peakHeadwayGivesShortExpectedWait() throws {
        let timetable = try Self.loadTimetable()
        // Tuesday (weekday 3) 08:20 -> peak period, 5 min headway -> 150 s expected.
        let time = WeekTimePoint(weekday: 3, secondsIntoDay: 8 * 3600 + 20 * 60)
        #expect(timetable.expectedWaitSeconds(line: ShuttleLineID("loop-red"), at: time) == 150)
    }

    @Test func offPeakHeadway() throws {
        let timetable = try Self.loadTimetable()
        // Tuesday 14:00 -> 8 min headway -> 240 s.
        let time = WeekTimePoint(weekday: 3, secondsIntoDay: 14 * 3600)
        #expect(timetable.expectedWaitSeconds(line: ShuttleLineID("loop-red"), at: time) == 240)
    }

    @Test func serviceClosedOvernight() throws {
        let timetable = try Self.loadTimetable()
        let time = WeekTimePoint(weekday: 3, secondsIntoDay: 2 * 3600)
        #expect(timetable.expectedWaitSeconds(line: ShuttleLineID("loop-red"), at: time) == nil)
    }

    @Test func weekendServiceUsesWeekendHeadway() throws {
        let timetable = try Self.loadTimetable()
        // Sunday (weekday 1) 11:00 -> 20 min headway -> 600 s.
        let time = WeekTimePoint(weekday: 1, secondsIntoDay: 11 * 3600)
        #expect(timetable.expectedWaitSeconds(line: ShuttleLineID("loop-blue"), at: time) == 600)
    }

    @Test func unknownLineHasNoService() throws {
        let timetable = try Self.loadTimetable()
        let time = WeekTimePoint(weekday: 3, secondsIntoDay: 10 * 3600)
        #expect(timetable.expectedWaitSeconds(line: ShuttleLineID("loop-purple"), at: time) == nil)
    }

    @Test func rideTimeIncludesDwell() throws {
        let timetable = try Self.loadTimetable()
        let ride = timetable.rideSeconds(forEdgeLength: 830)
        #expect(abs(ride - (830 / 8.3 + 20)) < 0.001)
    }

    @Test func weekTimePointAdvancesAcrossMidnight() {
        let late = WeekTimePoint(weekday: 3, secondsIntoDay: 23 * 3600)
        let advanced = late.advanced(bySeconds: 2 * 3600)
        #expect(advanced.weekday == 4)
        #expect(advanced.secondsIntoDay == 3600)
        // Saturday (7) wraps to Sunday (1).
        let saturday = WeekTimePoint(weekday: 7, secondsIntoDay: 23 * 3600)
        #expect(saturday.advanced(bySeconds: 2 * 3600).weekday == 1)
    }
}
