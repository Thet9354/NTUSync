import Foundation

/// Pure planning half of the leave-now feature: which class occurrences fall
/// inside the scheduling horizon, and when a notification should fire for one.
/// The EventKit-free math lives here so it is unit-testable; the
/// UNUserNotificationCenter side lives in `LeaveAlertScheduler`.
nonisolated enum LeaveAlertPlanner {
    /// iOS caps pending local notifications at 64; stay well below and let the
    /// next app launch roll the window forward.
    static let maxAlerts = 32
    static let horizonDays = 7

    /// All concrete class-start dates within the horizon, teaching-week aware.
    static func upcomingOccurrences(
        sessions: [SessionSnapshot],
        semesterStart: Date,
        now: Date,
        horizonDays: Int = LeaveAlertPlanner.horizonDays,
        calendar: Calendar = .current
    ) -> [(session: SessionSnapshot, classStart: Date)] {
        let teaching = TeachingCalendar(semesterStart: semesterStart, calendar: calendar)
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return [] }

        var occurrences: [(SessionSnapshot, Date)] = []
        for session in sessions {
            var after = now
            while let start = teaching.nextOccurrence(
                dayOfWeek: session.dayOfWeek,
                startMinutes: session.startMinutes,
                teachingWeeksMask: session.teachingWeeksMask,
                after: after
            ), start <= horizon {
                occurrences.append((session, start))
                after = start
            }
        }
        return occurrences
            .sorted { $0.1 < $1.1 }
            .prefix(maxAlerts)
            .map { $0 }
    }

    /// `classStart − routeTime − buffer`.
    static func fireDate(classStart: Date, travelSeconds: Double, bufferMinutes: Int) -> Date {
        classStart.addingTimeInterval(-(travelSeconds + Double(bufferMinutes) * 60))
    }
}
