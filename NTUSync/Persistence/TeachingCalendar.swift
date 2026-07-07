import Foundation

/// Pure recurrence math over the NTU semester structure:
/// 7 teaching weeks, 1 recess week, then teaching weeks 8–13.
nonisolated struct TeachingCalendar: Sendable {
    let semesterStart: Date        // normalized to start of day (Monday of week 1)
    private let calendar: Calendar

    init(semesterStart: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        self.semesterStart = calendar.startOfDay(for: semesterStart)
    }

    /// Teaching week (1…13) containing `date`, or nil for recess week,
    /// pre-semester, or post-semester dates.
    func teachingWeek(containing date: Date) -> Int? {
        let day = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: semesterStart, to: day).day,
              days >= 0 else { return nil }
        let calendarWeek = days / 7   // 0-based week since semester start
        switch calendarWeek {
        case 0...6: return calendarWeek + 1     // teaching weeks 1–7
        case 7: return nil                      // recess week
        case 8...13: return calendarWeek        // teaching weeks 8–13
        default: return nil
        }
    }

    /// Next concrete start `Date` of a recurring session strictly after `date`.
    func nextOccurrence(dayOfWeek: Int, startMinutes: Int, teachingWeeksMask: Int,
                        after date: Date) -> Date? {
        var day = calendar.startOfDay(for: max(date, semesterStart))
        // 15 calendar weeks bounds the whole semester incl. recess.
        for _ in 0..<(15 * 7) {
            if calendar.component(.weekday, from: day) == dayOfWeek,
               let week = teachingWeek(containing: day),
               teachingWeeksMask & (1 << (week - 1)) != 0,
               let candidate = calendar.date(byAdding: .minute, value: startMinutes, to: day),
               candidate > date {
                return candidate
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}
