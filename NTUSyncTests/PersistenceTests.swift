import Testing
import Foundation
import SwiftData
@testable import NTUSync

@MainActor
struct PersistenceTests {

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV4.self)
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
        #expect(benchesAfterFirst == 30)

        try await store.seedIfNeeded()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Venue>()) == venuesAfterFirst)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StudyBench>()) == benchesAfterFirst)
    }

    /// Real on-disk V1 → V2 migration: existing rows survive, new columns
    /// arrive nil/defaulted. In-memory containers can't exercise this.
    @Test func lightweightMigrationV1ToV2PreservesData() throws {
        let storeURL = URL.temporaryDirectory
            .appending(path: "migration-test-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-wal"))
        }

        // Write a V1-shaped store, then release the container.
        do {
            let v1 = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(v1)
            context.insert(SchemaV1.StudyBench(
                latitude: 1.3465, longitude: 103.6840, graphNodeID: "hive",
                hasPower: true, isSheltered: true, userRating: 4, note: "pilot bench"
            ))
            context.insert(SchemaV1.UserSettings(semesterStartDate: .now, seedVersion: 3))
            try context.save()
        }

        // Reopen at V2 through the migration plan.
        let v2 = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            migrationPlan: NTUSyncMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(v2)

        let benches = try context.fetch(FetchDescriptor<StudyBench>())
        #expect(benches.count == 1)
        #expect(benches.first?.note == "pilot bench")
        #expect(benches.first?.userRating == 4)
        #expect(benches.first?.photo == nil)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.seedVersion == 3)
        #expect(settings.first?.homeNodeID == nil)
        #expect(settings.first?.leaveAlertsEnabled == false)
        #expect(settings.first?.leaveBufferMinutes == 10)

        // The new entity is queryable on the migrated store.
        let photoCount = try context.fetchCount(FetchDescriptor<CheckpointPhoto>())
        #expect(photoCount == 0)
    }

    /// Real on-disk V2 → V3 migration: existing rows survive and the new
    /// ExamEvent entity is queryable on the migrated store.
    @Test func lightweightMigrationV2ToV3PreservesData() throws {
        let storeURL = URL.temporaryDirectory
            .appending(path: "migration-test-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-wal"))
        }

        // Write a V2-shaped store, then release the container.
        do {
            let v2 = try ModelContainer(
                for: Schema(versionedSchema: SchemaV2.self),
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(v2)
            context.insert(SchemaV2.UserSettings(semesterStartDate: .now, seedVersion: 5,
                                                 homeNodeID: "hall.6"))
            context.insert(SchemaV2.CheckpointPhoto(nodeID: "indoor.hive-atrium", photo: Data([7])))
            try context.save()
        }

        // Reopen at V3 through the migration plan.
        let v3 = try ModelContainer(
            for: Schema(versionedSchema: SchemaV3.self),
            migrationPlan: NTUSyncMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(v3)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.seedVersion == 5)
        #expect(settings.first?.homeNodeID == "hall.6")

        let photos = try context.fetch(FetchDescriptor<CheckpointPhoto>())
        #expect(photos.count == 1)
        #expect(photos.first?.photo == Data([7]))

        // The new entity is empty but queryable, and accepts inserts.
        #expect(try context.fetchCount(FetchDescriptor<ExamEvent>()) == 0)
        context.insert(ExamEvent(courseCode: "SC2005", date: .now, durationMinutes: 120))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ExamEvent>()) == 1)
    }

    /// Real on-disk V3 → V4 migration: existing rows survive and the new
    /// UserPlace entity is queryable on the migrated store.
    @Test func lightweightMigrationV3ToV4PreservesData() throws {
        let storeURL = URL.temporaryDirectory
            .appending(path: "migration-test-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-wal"))
        }

        // Write a V3-shaped store, then release the container.
        do {
            let v3 = try ModelContainer(
                for: Schema(versionedSchema: SchemaV3.self),
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(v3)
            context.insert(SchemaV3.ExamEvent(courseCode: "SC2005", date: .now,
                                              durationMinutes: 120, seatNumber: "A-042"))
            context.insert(SchemaV2.UserSettings(semesterStartDate: .now, seedVersion: 7))
            try context.save()
        }

        // Reopen at V4 through the migration plan.
        let v4 = try ModelContainer(
            for: Schema(versionedSchema: SchemaV4.self),
            migrationPlan: NTUSyncMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = ModelContext(v4)

        let exams = try context.fetch(FetchDescriptor<ExamEvent>())
        #expect(exams.count == 1)
        #expect(exams.first?.seatNumber == "A-042")
        #expect(try context.fetch(FetchDescriptor<UserSettings>()).first?.seedVersion == 7)

        // The new entity is empty but queryable, and accepts inserts.
        #expect(try context.fetchCount(FetchDescriptor<UserPlace>()) == 0)
        context.insert(UserPlace(name: "Mala stall", categoryRaw: "food",
                                 latitude: 1.344, longitude: 103.685,
                                 graphNodeID: "bldg.canteen2"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<UserPlace>()) == 1)
    }

    @Test func userPlaceRoundTripsAndMapsCategory() throws {
        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext

        context.insert(UserPlace(name: "Mala stall", categoryRaw: "food",
                                 latitude: 1.344, longitude: 103.685,
                                 graphNodeID: "bldg.canteen2", note: "open till late"))
        context.insert(UserPlace(name: "Secret spot", categoryRaw: nil,
                                 latitude: 1.345, longitude: 103.684,
                                 graphNodeID: "bldg.hive"))
        try context.save()

        let places = try context.fetch(FetchDescriptor<UserPlace>(sortBy: [SortDescriptor(\.name)]))
        #expect(places.count == 2)
        #expect(places[0].category == .food)
        #expect(places[0].icon == "fork.knife")
        #expect(places[1].category == nil)           // custom pin
        #expect(places[1].icon == "mappin")

        context.delete(places[0])
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<UserPlace>()) == 1)
    }

    @Test func examEventRoundTrips() throws {
        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext

        context.insert(ExamEvent(courseCode: "SC2005", date: .now.addingTimeInterval(86_400),
                                 durationMinutes: 120, venueName: "SRC Hall",
                                 seatNumber: "A-042"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ExamEvent>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.courseCode == "SC2005")
        #expect(fetched.first?.venueName == "SRC Hall")
        #expect(fetched.first?.seatNumber == "A-042")

        context.delete(fetched[0])
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ExamEvent>()) == 0)
    }

    @Test func benchPhotoRoundTrips() throws {
        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext

        let bench = StudyBench(latitude: 1.34, longitude: 103.68, graphNodeID: "bldg.hive",
                               hasPower: true, isSheltered: true)
        context.insert(bench)
        try context.save()

        bench.photo = Data([0xFF, 0xD8, 0xFF])
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StudyBench>())
        #expect(fetched.first?.photo == Data([0xFF, 0xD8, 0xFF]))

        bench.photo = nil
        try context.save()
        #expect(try context.fetch(FetchDescriptor<StudyBench>()).first?.photo == nil)
    }

    @Test func checkpointPhotoIsUniquePerNode() throws {
        let container = try Self.makeInMemoryContainer()
        let context = container.mainContext

        context.insert(CheckpointPhoto(nodeID: "indoor.hive-atrium", photo: Data([1])))
        try context.save()
        // #Unique on nodeID: a second insert for the same node upserts.
        context.insert(CheckpointPhoto(nodeID: "indoor.hive-atrium", photo: Data([2])))
        try context.save()

        let photos = try context.fetch(FetchDescriptor<CheckpointPhoto>())
        #expect(photos.count == 1)
        #expect(photos.first?.photo == Data([2]))
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
