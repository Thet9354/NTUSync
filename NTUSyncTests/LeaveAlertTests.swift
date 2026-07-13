import Testing
import Foundation
@testable import NTUSync

struct LeaveAlertPlannerTests {

    // Monday, 10 Aug 2026 — teaching week 1.
    static var semesterStart: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 10
        return Calendar.current.date(from: components)!
    }

    static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return Calendar.current.date(from: components)!
    }

    static func session(dayOfWeek: Int, startMinutes: Int = 630,
                        mask: Int = 0b1_1111_1111_1111) -> SessionSnapshot {
        SessionSnapshot(courseCode: "CZ2007", courseTitle: "DBMS", kind: .lecture,
                        dayOfWeek: dayOfWeek, startMinutes: startMinutes, durationMinutes: 60,
                        teachingWeeksMask: mask, venueName: "LT19", venueNodeID: "bldg.spms")
    }

    @Test func horizonCollectsEveryOccurrenceOfTheComingWeek() {
        // Sunday evening before week 2: a Mon+Fri session yields exactly the
        // week-2 Monday and Friday occurrences inside a 7-day horizon.
        let now = Self.day(2026, 8, 16, hour: 20)
        let occurrences = LeaveAlertPlanner.upcomingOccurrences(
            sessions: [Self.session(dayOfWeek: 2), Self.session(dayOfWeek: 6)],
            semesterStart: Self.semesterStart,
            now: now
        )
        #expect(occurrences.map(\.classStart) == [
            Self.day(2026, 8, 17, hour: 10, minute: 30),
            Self.day(2026, 8, 21, hour: 10, minute: 30),
        ])
    }

    @Test func recessWeekProducesNoOccurrences() {
        // Recess is 28 Sep – 4 Oct 2026; a horizon inside it is empty for an
        // all-weeks session, and the first hit after it is week-8 Monday.
        let insideRecess = LeaveAlertPlanner.upcomingOccurrences(
            sessions: [Self.session(dayOfWeek: 2)],
            semesterStart: Self.semesterStart,
            now: Self.day(2026, 9, 27, hour: 12),
            horizonDays: 6
        )
        #expect(insideRecess.isEmpty)

        let acrossRecess = LeaveAlertPlanner.upcomingOccurrences(
            sessions: [Self.session(dayOfWeek: 2)],
            semesterStart: Self.semesterStart,
            now: Self.day(2026, 9, 27, hour: 12),
            horizonDays: 9
        )
        #expect(acrossRecess.map(\.classStart) == [Self.day(2026, 10, 5, hour: 10, minute: 30)])
    }

    @Test func occurrencesAreChronologicalAndCapped() {
        // 40 fake sessions on the same day would exceed the cap of 32.
        let sessions = (0..<40).map { i in
            SessionSnapshot(courseCode: "C\(i)", courseTitle: "t", kind: .lecture,
                            dayOfWeek: 2, startMinutes: 480 + i, durationMinutes: 60,
                            teachingWeeksMask: 0b1_1111_1111_1111,
                            venueName: nil, venueNodeID: nil)
        }
        let occurrences = LeaveAlertPlanner.upcomingOccurrences(
            sessions: sessions,
            semesterStart: Self.semesterStart,
            now: Self.day(2026, 8, 16, hour: 20)
        )
        #expect(occurrences.count == LeaveAlertPlanner.maxAlerts)
        let starts = occurrences.map(\.classStart)
        #expect(starts == starts.sorted())
    }

    @Test func fireDateSubtractsRouteAndBuffer() {
        let classStart = Self.day(2026, 8, 17, hour: 10, minute: 30)
        let fire = LeaveAlertPlanner.fireDate(classStart: classStart,
                                              travelSeconds: 18 * 60, bufferMinutes: 10)
        #expect(fire == Self.day(2026, 8, 17, hour: 10, minute: 2))
    }
}
