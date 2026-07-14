import Foundation

/// Sendable projection of an ExamEvent for pure countdown math (models stay
/// on @MainActor).
nonisolated struct ExamSnapshot: Sendable, Hashable {
    let courseCode: String
    let date: Date
    let durationMinutes: Int
    let venueName: String?
    let seatNumber: String?

    var end: Date { date.addingTimeInterval(Double(durationMinutes) * 60) }
}

/// Where an exam sits relative to `now` — drives the countdown badge.
nonisolated enum ExamPhase: Equatable, Sendable {
    /// One or more calendar days away.
    case upcoming(daysAway: Int)
    /// Later today.
    case today(minutesUntil: Int)
    /// Started, not yet over.
    case inProgress(minutesRemaining: Int)
    case finished
}

/// Pure countdown and ordering logic for one-off exam events.
nonisolated enum ExamPlanner {

    static func phase(of exam: ExamSnapshot, now: Date,
                      calendar: Calendar = .current) -> ExamPhase {
        if now >= exam.end { return .finished }
        if now >= exam.date {
            let remaining = Int((exam.end.timeIntervalSince(now) / 60).rounded(.up))
            return .inProgress(minutesRemaining: remaining)
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: exam.date)
        ).day ?? 0
        if days <= 0 {
            return .today(minutesUntil: Int(exam.date.timeIntervalSince(now) / 60))
        }
        return .upcoming(daysAway: days)
    }

    /// Exams not yet over, soonest first.
    static func upcoming(_ exams: [ExamSnapshot], now: Date) -> [ExamSnapshot] {
        exams.filter { now < $0.end }.sorted { $0.date < $1.date }
    }

    /// Exams already over, most recent first.
    static func completed(_ exams: [ExamSnapshot], now: Date) -> [ExamSnapshot] {
        exams.filter { now >= $0.end }.sorted { $0.date > $1.date }
    }
}
