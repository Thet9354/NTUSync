import Testing
import Foundation
@testable import NTUSync

struct ICSExportTests {

    static func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var components = DateComponents()
        components.year = y; components.month = mo; components.day = d
        components.hour = h; components.minute = mi
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    static func event(title: String = "SC2005 Lecture", location: String? = "LT19",
                      week: Int = 3) -> PlannedEvent {
        PlannedEvent(title: title, location: location,
                     start: utc(2026, 8, 11, 1, 0), end: utc(2026, 8, 11, 2, 0),
                     teachingWeek: week)
    }

    @Test func producesWellFormedVCalendar() {
        let ics = ICSExporter.makeCalendar(from: [Self.event()], now: Self.utc(2026, 7, 14, 0, 0))
        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(ics.contains("\r\nVERSION:2.0\r\n"))
        #expect(ics.contains("\r\nPRODID:-//NTUSync//Timetable Export//EN\r\n"))
        #expect(ics.contains("\r\nBEGIN:VEVENT\r\n"))
        #expect(ics.contains("\r\nDTSTART:20260811T010000Z\r\n"))
        #expect(ics.contains("\r\nDTEND:20260811T020000Z\r\n"))
        #expect(ics.contains("\r\nDTSTAMP:20260714T000000Z\r\n"))
        #expect(ics.contains("\r\nSUMMARY:SC2005 Lecture\r\n"))
        #expect(ics.contains("\r\nLOCATION:LT19\r\n"))
        #expect(ics.contains("\r\nEND:VEVENT\r\n"))
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
    }

    @Test func nilLocationIsOmitted() {
        let ics = ICSExporter.makeCalendar(from: [Self.event(location: nil)])
        #expect(!ics.contains("LOCATION:"))
    }

    @Test func escapesTextSpecialCharacters() {
        let ics = ICSExporter.makeCalendar(from: [Self.event(title: "A, B; C\\D")])
        #expect(ics.contains("SUMMARY:A\\, B\\; C\\\\D"))
    }

    @Test func eachEventGetsAUniqueUID() {
        let events = [Self.event(week: 1), Self.event(week: 3)]
        let ics = ICSExporter.makeCalendar(from: events)
        let uids = ics.components(separatedBy: "\r\n").filter { $0.hasPrefix("UID:") }
        #expect(uids.count == 2)
        #expect(Set(uids).count == 2)
    }

    @Test func emptyScheduleStillProducesValidShell() {
        let ics = ICSExporter.makeCalendar(from: [])
        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
        #expect(!ics.contains("BEGIN:VEVENT"))
    }

    @Test func longLinesFoldToSeventyFiveOctets() {
        let long = String(repeating: "x", count: 200)
        let folded = ICSExporter.fold("SUMMARY:" + long)
        let physical = folded.components(separatedBy: "\r\n")
        #expect(physical.count > 1)
        for line in physical {
            #expect(line.utf8.count <= 75)
        }
        // Unfolding (drop the leading space on continuations) restores the original.
        let unfolded = physical.enumerated()
            .map { $0.offset == 0 ? $0.element : String($0.element.dropFirst()) }
            .joined()
        #expect(unfolded == "SUMMARY:" + long)
    }

    /// End-to-end: reuse TimetableEventPlanner's expansion, then serialise.
    @Test func expandsSemesterThroughPlanner() {
        let snapshot = SessionSnapshot(
            courseCode: "SC2005", courseTitle: "Data Structures", kind: .lecture,
            dayOfWeek: 2, startMinutes: 600, durationMinutes: 60,
            teachingWeeksMask: 0b1_0101_0101_0101, venueName: "LT19")
        let events = TimetableEventPlanner.events(
            for: [snapshot], semesterStart: WeekGridTests.semesterStart)
        let ics = ICSExporter.makeCalendar(from: events)
        // Odd weeks 1,3,5,7,9,11,13 → 7 occurrences.
        let vevents = ics.components(separatedBy: "BEGIN:VEVENT").count - 1
        #expect(vevents == 7)
    }
}
