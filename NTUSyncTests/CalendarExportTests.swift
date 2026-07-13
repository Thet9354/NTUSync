import Testing
import Foundation
@testable import NTUSync

struct TimetableEventPlannerTests {

    // Monday, 10 Aug 2026 — teaching week 1 (same anchor as TeachingCalendarTests).
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

    static func snapshot(dayOfWeek: Int = 2, startMinutes: Int = 630, duration: Int = 60,
                         mask: Int = 0b1_1111_1111_1111, venue: String? = "LT19") -> SessionSnapshot {
        SessionSnapshot(courseCode: "SC2005", courseTitle: "Operating Systems",
                        kind: .lecture, dayOfWeek: dayOfWeek, startMinutes: startMinutes,
                        durationMinutes: duration, teachingWeeksMask: mask, venueName: venue)
    }

    @Test func allWeeksSessionYieldsThirteenEventsSkippingRecess() {
        let events = TimetableEventPlanner.events(for: [Self.snapshot()],
                                                  semesterStart: Self.semesterStart)
        #expect(events.count == 13)
        // Week 1: Monday 10 Aug 10:30–11:30.
        #expect(events.first?.start == Self.day(2026, 8, 10, hour: 10, minute: 30))
        #expect(events.first?.end == Self.day(2026, 8, 10, hour: 11, minute: 30))
        // Week 7 is Mon 21 Sep; recess Mon 28 Sep must NOT appear; week 8 is Mon 5 Oct.
        let starts = Set(events.map(\.start))
        #expect(starts.contains(Self.day(2026, 9, 21, hour: 10, minute: 30)))
        #expect(!starts.contains(Self.day(2026, 9, 28, hour: 10, minute: 30)))
        #expect(starts.contains(Self.day(2026, 10, 5, hour: 10, minute: 30)))
        // Week 13: Mon 9 Nov.
        #expect(events.last?.start == Self.day(2026, 11, 9, hour: 10, minute: 30))
    }

    @Test func oddWeekMaskExpandsToSevenDatedEvents() {
        let events = TimetableEventPlanner.events(
            for: [Self.snapshot(mask: 0b1_0101_0101_0101)],
            semesterStart: Self.semesterStart
        )
        #expect(events.count == 7)
        #expect(events.map(\.teachingWeek) == [1, 3, 5, 7, 9, 11, 13])
    }

    @Test func weekdayOffsetAndTitleFormatting() {
        // Friday (weekday 6) 14:00, even weeks: first occurrence Fri of week 2 = 21 Aug.
        let events = TimetableEventPlanner.events(
            for: [Self.snapshot(dayOfWeek: 6, startMinutes: 840, mask: 0b0_1010_1010_1010)],
            semesterStart: Self.semesterStart
        )
        #expect(events.first?.start == Self.day(2026, 8, 21, hour: 14))
        #expect(events.first?.title == "SC2005 Lecture")
        #expect(events.first?.location == "LT19")
    }

    @Test func multipleSessionsAreSortedChronologically() {
        let events = TimetableEventPlanner.events(
            for: [Self.snapshot(dayOfWeek: 6), Self.snapshot(dayOfWeek: 2)],
            semesterStart: Self.semesterStart
        )
        #expect(events.count == 26)
        let sorted = events.map(\.start)
        #expect(sorted == sorted.sorted())
    }
}
