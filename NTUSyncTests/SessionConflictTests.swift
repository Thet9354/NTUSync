import Testing
import Foundation
@testable import NTUSync

struct SessionConflictTests {

    static func slot(label: String = "SC2005 Lecture", day: Int = 2, start: Int = 600,
                     duration: Int = 60, mask: Int = 0b1_1111_1111_1111) -> ScheduleSlot {
        ScheduleSlot(label: label, dayOfWeek: day, startMinutes: start,
                     durationMinutes: duration, teachingWeeksMask: mask)
    }

    @Test func sameTimeSameDaySameWeeksConflicts() {
        #expect(SessionConflictDetector.overlaps(Self.slot(), Self.slot(label: "CZ2007 Tutorial")))
    }

    @Test func differentWeekdaysNeverConflict() {
        #expect(!SessionConflictDetector.overlaps(Self.slot(day: 2), Self.slot(day: 3)))
    }

    @Test func backToBackDoesNotConflict() {
        let a = Self.slot(start: 600, duration: 60)   // 10:00–11:00
        let b = Self.slot(start: 660, duration: 60)   // 11:00–12:00
        #expect(!SessionConflictDetector.overlaps(a, b))
    }

    @Test func partialOverlapConflicts() {
        let a = Self.slot(start: 600, duration: 60)   // 10:00–11:00
        let b = Self.slot(start: 630, duration: 60)   // 10:30–11:30
        #expect(SessionConflictDetector.overlaps(a, b))
    }

    @Test func disjointTeachingWeeksDoNotConflict() {
        let odd = Self.slot(mask: 0b1_0101_0101_0101)
        let even = Self.slot(mask: 0b0_1010_1010_1010)
        #expect(!SessionConflictDetector.overlaps(odd, even))
    }

    @Test func overlappingWeeksReturnsSharedWeeks() {
        let all = Self.slot(mask: 0b1_1111_1111_1111)
        let odd = Self.slot(mask: 0b1_0101_0101_0101)
        #expect(SessionConflictDetector.overlappingWeeks(all, odd) == [1, 3, 5, 7, 9, 11, 13])
        // No overlap at all → empty.
        #expect(SessionConflictDetector.overlappingWeeks(odd, Self.slot(mask: 0b0_1010_1010_1010)).isEmpty)
    }

    @Test func conflictsForCandidateFiltersExisting() {
        // Candidate runs odd weeks only.
        let candidate = Self.slot(start: 600, mask: 0b1_0101_0101_0101)
        let existing = [
            Self.slot(label: "A", start: 630),    // overlaps (all weeks ∩ odd ≠ ∅)
            Self.slot(label: "B", day: 3),        // other weekday
            Self.slot(label: "C", start: 660),    // back-to-back, no time overlap
            Self.slot(label: "D", start: 600, mask: 0b0_1010_1010_1010), // even weeks, disjoint
        ]
        let conflicts = SessionConflictDetector.conflicts(for: candidate, against: existing)
        #expect(conflicts.map(\.label) == ["A"])
    }

    @Test func conflictingIndicesFlagsBothSidesOnce() {
        let slots = [
            Self.slot(label: "A", start: 600),
            Self.slot(label: "B", start: 630),    // clashes with A
            Self.slot(label: "C", day: 4),        // alone
        ]
        #expect(SessionConflictDetector.conflictingIndices(in: slots) == [0, 1])
    }

    @Test func noConflictsYieldsEmptyIndexSet() {
        let slots = [Self.slot(start: 600), Self.slot(start: 660), Self.slot(day: 3)]
        #expect(SessionConflictDetector.conflictingIndices(in: slots).isEmpty)
    }
}
