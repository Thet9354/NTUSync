import Foundation
import SwiftData

/// Version 3: exam mode. `ExamEvent` is brand new; every other model is
/// unchanged from V2 (so they're referenced, not redeclared), making V2 → V3 a
/// lightweight stage.
nonisolated enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Course.self, ClassSession.self, Venue.self,
         SchemaV2.StudyBench.self, SchemaV2.UserSettings.self, SchemaV2.CheckpointPhoto.self,
         ExamEvent.self]
    }

    /// One-off assessed event — final exam, quiz, presentation. A concrete
    /// date+time rather than a weekly recurrence, plus the seat number you can
    /// never remember on the day. Tied to a course by code STRING (the same
    /// string-key philosophy as `graphNodeID`), so an exam survives its
    /// course's deletion and works for courses not in the timetable at all.
    @Model
    nonisolated final class ExamEvent {
        var courseCode: String
        /// Exam start (date and time).
        var date: Date
        var durationMinutes: Int
        /// Free text — exam venues (sports halls, marquees) often aren't
        /// teaching venues, so this deliberately isn't a `Venue` relationship.
        var venueName: String?
        var seatNumber: String?
        var note: String?

        init(courseCode: String, date: Date, durationMinutes: Int,
             venueName: String? = nil, seatNumber: String? = nil, note: String? = nil) {
            self.courseCode = courseCode
            self.date = date
            self.durationMinutes = durationMinutes
            self.venueName = venueName
            self.seatNumber = seatNumber
            self.note = note
        }
    }
}

/// The rest of the app always talks to the *current* schema version.
typealias ExamEvent = SchemaV3.ExamEvent

nonisolated enum NTUSyncMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
         .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)]
    }
}
