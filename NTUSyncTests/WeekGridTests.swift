import Testing
import Foundation
@testable import NTUSync

struct WeekGridTests {

    // Monday, 10 Aug 2026 — teaching week 1 (shared anchor).
    static var semesterStart: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 10
        return Calendar.current.date(from: components)!
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        return Calendar.current.date(from: components)!
    }

    static func session(dayOfWeek: Int = 2, startMinutes: Int = 630,
                        mask: Int = 0b1_1111_1111_1111,
                        code: String = "SC2005") -> WeekGridSession {
        WeekGridSession(courseCode: code, colorSeed: 3, kind: .lecture,
                        dayOfWeek: dayOfWeek, startMinutes: startMinutes,
                        durationMinutes: 60, teachingWeeksMask: mask,
                        venueShortName: "LT19")
    }

    @Test func oddWeekSessionOccupiesOnlyOddWeekCells() {
        let odd = Self.session(mask: 0b1_0101_0101_0101)
        for week in 1...13 {
            let entries = WeekGrid.entries(week: week, weekday: 2, sessions: [odd])
            #expect(entries.isEmpty == (week % 2 == 0),
                    "week \(week) should be \(week % 2 == 1 ? "occupied" : "empty")")
        }
        // Wrong weekday is always empty.
        #expect(WeekGrid.entries(week: 1, weekday: 3, sessions: [odd]).isEmpty)
    }

    @Test func weekendColumnsAppearOnlyWhenUsed() {
        let weekdayOnly = [Self.session(dayOfWeek: 2), Self.session(dayOfWeek: 6)]
        #expect(WeekGrid.weekdayColumns(for: weekdayOnly) == [2, 3, 4, 5, 6])

        let withSaturday = weekdayOnly + [Self.session(dayOfWeek: 7)]
        #expect(WeekGrid.weekdayColumns(for: withSaturday) == [2, 3, 4, 5, 6, 7])

        let withBoth = withSaturday + [Self.session(dayOfWeek: 1)]
        #expect(WeekGrid.weekdayColumns(for: withBoth) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func cellEntriesAreChronological() {
        let sessions = [
            Self.session(startMinutes: 840, code: "CZ2007"),
            Self.session(startMinutes: 540, code: "SC2005"),
            Self.session(startMinutes: 630, code: "MH1812"),
        ]
        let entries = WeekGrid.entries(week: 1, weekday: 2, sessions: sessions)
        #expect(entries.map(\.courseCode) == ["SC2005", "MH1812", "CZ2007"])
    }

    @Test func mondayDatesSkipRecessWeek() {
        // Week 7 Monday is 21 Sep; week 8 Monday jumps the recess to 5 Oct.
        #expect(WeekGrid.mondayDate(ofTeachingWeek: 1, semesterStart: Self.semesterStart)
                == Self.day(2026, 8, 10))
        #expect(WeekGrid.mondayDate(ofTeachingWeek: 7, semesterStart: Self.semesterStart)
                == Self.day(2026, 9, 21))
        #expect(WeekGrid.mondayDate(ofTeachingWeek: 8, semesterStart: Self.semesterStart)
                == Self.day(2026, 10, 5))
        #expect(WeekGrid.mondayDate(ofTeachingWeek: 13, semesterStart: Self.semesterStart)
                == Self.day(2026, 11, 9))
        #expect(WeekGrid.mondayDate(ofTeachingWeek: 0, semesterStart: Self.semesterStart) == nil)
        #expect(WeekGrid.mondayDate(ofTeachingWeek: 14, semesterStart: Self.semesterStart) == nil)
    }
}
