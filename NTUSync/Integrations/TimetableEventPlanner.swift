import Foundation

/// One concrete dated calendar event for a class session occurrence.
nonisolated struct PlannedEvent: Sendable, Hashable {
    let title: String
    let location: String?
    let start: Date
    let end: Date
    let teachingWeek: Int
}

/// Sendable projection of a ClassSession + its course/venue for export and
/// alert planning (models can't cross actor boundaries).
nonisolated struct SessionSnapshot: Sendable, Hashable {
    let courseCode: String
    let courseTitle: String
    let kind: SessionKind
    let dayOfWeek: Int          // Calendar weekday, 1 = Sunday … 7 = Saturday
    let startMinutes: Int
    let durationMinutes: Int
    let teachingWeeksMask: Int
    let venueName: String?
    /// Graph join for routing-dependent features (leave-now alerts).
    let venueNodeID: String?

    init(courseCode: String, courseTitle: String, kind: SessionKind, dayOfWeek: Int,
         startMinutes: Int, durationMinutes: Int, teachingWeeksMask: Int,
         venueName: String?, venueNodeID: String? = nil) {
        self.courseCode = courseCode
        self.courseTitle = courseTitle
        self.kind = kind
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.teachingWeeksMask = teachingWeeksMask
        self.venueName = venueName
        self.venueNodeID = venueNodeID
    }
}

@MainActor
extension SessionSnapshot {
    /// Flatten persisted courses into snapshots.
    static func snapshots(of courses: [Course]) -> [SessionSnapshot] {
        courses.flatMap { course in
            course.sessions.map { session in
                SessionSnapshot(
                    courseCode: course.code,
                    courseTitle: course.title,
                    kind: session.kind,
                    dayOfWeek: session.dayOfWeek,
                    startMinutes: session.startMinutes,
                    durationMinutes: session.durationMinutes,
                    teachingWeeksMask: session.teachingWeeksMask,
                    venueName: session.venue.map { "\($0.displayName) (\($0.shortName))" },
                    venueNodeID: session.venue?.graphNodeID
                )
            }
        }
    }
}

/// Pure expansion of recurring sessions into individual dated events — one
/// event per active teaching week, NOT an RRULE, so odd/even weeks and the
/// recess week stay correct in any calendar app.
nonisolated enum TimetableEventPlanner {

    static func events(
        for sessions: [SessionSnapshot],
        semesterStart: Date,
        calendar: Calendar = .current
    ) -> [PlannedEvent] {
        let weekOneMonday = calendar.startOfDay(for: semesterStart)
        var events: [PlannedEvent] = []

        for session in sessions {
            // Days from Monday to the session's weekday within one week.
            let dayOffset = (session.dayOfWeek - 2 + 7) % 7
            for week in 1...13 where session.teachingWeeksMask & (1 << (week - 1)) != 0 {
                // Teaching weeks 1–7 are calendar weeks 0–6; recess occupies
                // calendar week 7; teaching weeks 8–13 are calendar weeks 8–13.
                let calendarWeek = week <= 7 ? week - 1 : week
                guard let day = calendar.date(byAdding: .day,
                                              value: calendarWeek * 7 + dayOffset,
                                              to: weekOneMonday),
                      let start = calendar.date(byAdding: .minute,
                                                value: session.startMinutes, to: day),
                      let end = calendar.date(byAdding: .minute,
                                              value: session.durationMinutes, to: start)
                else { continue }
                events.append(PlannedEvent(
                    title: "\(session.courseCode) \(session.kind.rawValue.capitalized)",
                    location: session.venueName,
                    start: start,
                    end: end,
                    teachingWeek: week
                ))
            }
        }
        return events.sorted { $0.start < $1.start }
    }
}
