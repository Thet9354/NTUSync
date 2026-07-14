import Testing
import Foundation
@testable import NTUSync

struct ExamTests {

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y; components.month = mo; components.day = d
        components.hour = h; components.minute = mi
        return Calendar.current.date(from: components)!
    }

    static func exam(date: Date, duration: Int = 120, code: String = "SC2005") -> ExamSnapshot {
        ExamSnapshot(courseCode: code, date: date, durationMinutes: duration,
                     venueName: "SRC Hall", seatNumber: "A-042")
    }

    // Exam: 20 Nov 2026, 09:00–11:00.
    static let examDay = date(2026, 11, 20, 9, 0)

    @Test func phaseDaysAway() {
        let exam = Self.exam(date: Self.examDay)
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 11, 10, 12, 0))
                == .upcoming(daysAway: 10))
        // Evening before is still "tomorrow" even though < 24h away.
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 11, 19, 22, 0))
                == .upcoming(daysAway: 1))
    }

    @Test func phaseTodayCountsMinutes() {
        let exam = Self.exam(date: Self.examDay)
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 11, 20, 7, 15))
                == .today(minutesUntil: 105))
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 11, 20, 8, 59))
                == .today(minutesUntil: 1))
    }

    @Test func phaseInProgressAndFinishedBoundaries() {
        let exam = Self.exam(date: Self.examDay, duration: 120)
        // At the exact start: in progress with the full duration remaining.
        #expect(ExamPlanner.phase(of: exam, now: Self.examDay)
                == .inProgress(minutesRemaining: 120))
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 11, 20, 10, 30))
                == .inProgress(minutesRemaining: 30))
        // At the exact end: finished.
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 11, 20, 11, 0)) == .finished)
        #expect(ExamPlanner.phase(of: exam, now: Self.date(2026, 12, 1)) == .finished)
    }

    @Test func upcomingSortsSoonestFirstAndDropsFinished() {
        let now = Self.date(2026, 11, 1)
        let exams = [
            Self.exam(date: Self.date(2026, 11, 25), code: "CZ2007"),
            Self.exam(date: Self.date(2026, 11, 20), code: "SC2005"),
            Self.exam(date: Self.date(2026, 10, 10), code: "MH1812"),   // already over
        ]
        #expect(ExamPlanner.upcoming(exams, now: now).map(\.courseCode) == ["SC2005", "CZ2007"])
    }

    @Test func completedSortsMostRecentFirst() {
        let now = Self.date(2026, 12, 1)
        let exams = [
            Self.exam(date: Self.date(2026, 11, 20), code: "SC2005"),
            Self.exam(date: Self.date(2026, 11, 25), code: "CZ2007"),
            Self.exam(date: Self.date(2027, 1, 5), code: "MH1812"),     // still ahead
        ]
        #expect(ExamPlanner.completed(exams, now: now).map(\.courseCode) == ["CZ2007", "SC2005"])
    }

    @Test func inProgressExamStaysInUpcoming() {
        // Mid-exam it should still be listed (as in-progress), not "completed".
        let now = Self.date(2026, 11, 20, 10, 0)
        let exams = [Self.exam(date: Self.examDay)]
        #expect(ExamPlanner.upcoming(exams, now: now).count == 1)
        #expect(ExamPlanner.completed(exams, now: now).isEmpty)
    }

    @Test func snapshotEndAddsDuration() {
        let exam = Self.exam(date: Self.examDay, duration: 90)
        #expect(exam.end == Self.date(2026, 11, 20, 10, 30))
    }
}
