import Testing
import Foundation
import SwiftData
@testable import NTUSync

@MainActor
struct PersistenceTests {

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    @Test func deletingCourseCascadesToSessions() throws {
        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext

        let course = Course(code: "SC2005", title: "Operating Systems")
        course.sessions.append(ClassSession(kind: .lecture, dayOfWeek: 2, startMinutes: 630, durationMinutes: 60))
        course.sessions.append(ClassSession(kind: .lab, dayOfWeek: 4, startMinutes: 990, durationMinutes: 120))
        context.insert(course)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ClassSession>()) == 2)

        context.delete(course)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ClassSession>()) == 0)
    }

    @Test func teachingWeeksMaskSemantics() {
        let oddWeeks = ClassSession(kind: .tutorial, dayOfWeek: 3, startMinutes: 540,
                                    durationMinutes: 60, teachingWeeksMask: 0b1_0101_0101_0101)
        #expect(oddWeeks.runsInTeachingWeek(1))
        #expect(!oddWeeks.runsInTeachingWeek(2))
        #expect(oddWeeks.runsInTeachingWeek(13))
        #expect(!oddWeeks.runsInTeachingWeek(0))
        #expect(!oddWeeks.runsInTeachingWeek(14))
    }

    @Test func seedIsIdempotent() async throws {
        let container = try Self.makeInMemoryContainer()
        let store = PersistenceStore(modelContainer: container)

        try await store.seedIfNeeded()
        let venuesAfterFirst = try container.mainContext.fetchCount(FetchDescriptor<Venue>())
        let benchesAfterFirst = try container.mainContext.fetchCount(FetchDescriptor<StudyBench>())
        #expect(venuesAfterFirst == 8)
        #expect(benchesAfterFirst == 6)

        try await store.seedIfNeeded()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Venue>()) == venuesAfterFirst)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StudyBench>()) == benchesAfterFirst)
    }

    @Test func seededVenuesReferenceRealGraphNodes() async throws {
        let container = try Self.makeInMemoryContainer()
        let store = PersistenceStore(modelContainer: container)
        try await store.seedIfNeeded()
        let graph = try CampusGraph.loadBundled()
        let venues = try container.mainContext.fetch(FetchDescriptor<Venue>())
        for venue in venues {
            #expect(graph.nodes[NodeID(venue.graphNodeID)] != nil,
                    "venue \(venue.shortName) references unknown node \(venue.graphNodeID)")
        }
    }
}

struct TeachingCalendarTests {

    static var semesterStart: Date {
        // Monday, 10 Aug 2026 — teaching week 1.
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 10
        return Calendar.current.date(from: components)!
    }

    static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return Calendar.current.date(from: components)!
    }

    @Test func weekMappingIncludingRecess() {
        let calendar = TeachingCalendar(semesterStart: Self.semesterStart)
        #expect(calendar.teachingWeek(containing: Self.day(2026, 8, 12)) == 1)
        #expect(calendar.teachingWeek(containing: Self.day(2026, 9, 22)) == 7)   // last day range of week 7
        #expect(calendar.teachingWeek(containing: Self.day(2026, 9, 28)) == nil) // recess week
        #expect(calendar.teachingWeek(containing: Self.day(2026, 10, 5)) == 8)   // teaching resumes
        #expect(calendar.teachingWeek(containing: Self.day(2026, 8, 9)) == nil)  // pre-semester
        #expect(calendar.teachingWeek(containing: Self.day(2027, 1, 4)) == nil)  // post-semester
    }

    @Test func nextOccurrenceHonoursWeekMask() {
        let calendar = TeachingCalendar(semesterStart: Self.semesterStart)
        let afterWeek1Tuesday = Self.day(2026, 8, 11)  // Tuesday of teaching week 1

        // Monday 10:00, odd weeks only -> next is Monday of week 3 (24 Aug).
        let odd = calendar.nextOccurrence(dayOfWeek: 2, startMinutes: 600,
                                          teachingWeeksMask: 0b1_0101_0101_0101,
                                          after: afterWeek1Tuesday)
        #expect(odd == Self.day(2026, 8, 24, hour: 10))

        // Monday 10:00, even weeks -> Monday of week 2 (17 Aug).
        let even = calendar.nextOccurrence(dayOfWeek: 2, startMinutes: 600,
                                           teachingWeeksMask: 0b0_1010_1010_1010,
                                           after: afterWeek1Tuesday)
        #expect(even == Self.day(2026, 8, 17, hour: 10))
    }

    @Test func nextOccurrenceSkipsRecessWeek() {
        let calendar = TeachingCalendar(semesterStart: Self.semesterStart)
        // Friday of week 7 is 25 Sep; a Friday session's next run after that is
        // Friday of week 8 (9 Oct), skipping recess Friday 2 Oct.
        let afterWeek7Friday = Self.day(2026, 9, 25, hour: 18)
        let next = calendar.nextOccurrence(dayOfWeek: 6, startMinutes: 540,
                                           teachingWeeksMask: 0b1_1111_1111_1111,
                                           after: afterWeek7Friday)
        #expect(next == Self.day(2026, 10, 9, hour: 9))
    }
}
