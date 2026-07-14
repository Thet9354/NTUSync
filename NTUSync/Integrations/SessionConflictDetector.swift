import Foundation

/// Sendable projection of a session's scheduling shape — everything needed to
/// decide whether two sessions collide, and nothing that touches persistence.
nonisolated struct ScheduleSlot: Sendable, Hashable {
    /// Human label for the conflicting session, e.g. "SC2005 Lecture".
    let label: String
    /// `Calendar` weekday convention: 1 = Sunday … 7 = Saturday.
    let dayOfWeek: Int
    let startMinutes: Int
    let durationMinutes: Int
    let teachingWeeksMask: Int

    var endMinutes: Int { startMinutes + durationMinutes }
}

/// Pure clash detection: two sessions conflict when they fall on the same
/// weekday, share at least one teaching week (bitmask intersection), and their
/// minute-of-day ranges overlap. All three tests are cheap integer arithmetic.
nonisolated enum SessionConflictDetector {

    /// Do these two slots collide on the same weekday, in an overlapping
    /// teaching week, at an overlapping time of day?
    static func overlaps(_ a: ScheduleSlot, _ b: ScheduleSlot) -> Bool {
        guard a.dayOfWeek == b.dayOfWeek else { return false }
        guard a.teachingWeeksMask & b.teachingWeeksMask != 0 else { return false }
        // Half-open ranges: back-to-back sessions (one ends as the next starts)
        // do NOT overlap.
        return a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes
    }

    /// The teaching weeks (1…13) in which two overlapping slots both run.
    static func overlappingWeeks(_ a: ScheduleSlot, _ b: ScheduleSlot) -> [Int] {
        let shared = a.teachingWeeksMask & b.teachingWeeksMask
        return (1...13).filter { shared & (1 << ($0 - 1)) != 0 }
    }

    /// Every existing slot that clashes with `candidate`, in input order.
    static func conflicts(for candidate: ScheduleSlot,
                          against existing: [ScheduleSlot]) -> [ScheduleSlot] {
        existing.filter { overlaps(candidate, $0) }
    }

    /// Indices of all slots that clash with at least one other slot in the set —
    /// used to flag pre-existing conflicts already sitting in the timetable.
    static func conflictingIndices(in slots: [ScheduleSlot]) -> Set<Int> {
        var clashing: Set<Int> = []
        for i in slots.indices {
            for j in slots.indices where j > i && overlaps(slots[i], slots[j]) {
                clashing.insert(i)
                clashing.insert(j)
            }
        }
        return clashing
    }
}
