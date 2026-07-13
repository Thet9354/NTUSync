import Foundation
import SwiftData

nonisolated enum SessionKind: String, Codable, CaseIterable, Sendable {
    case lecture, tutorial, lab, seminar
}

/// Version 1 of the store. `Course`/`ClassSession`/`Venue` are unchanged across
/// versions and stay top-level; models whose shape evolved live inside the
/// version namespace so every schema version stays reconstructible.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Course.self, ClassSession.self, Venue.self, StudyBench.self, UserSettings.self]
    }

    @Model
    nonisolated final class StudyBench {
        var latitude: Double
        var longitude: Double
        var graphNodeID: String
        var hasPower: Bool
        var isSheltered: Bool
        var userRating: Int?
        var note: String?

        init(latitude: Double, longitude: Double, graphNodeID: String,
             hasPower: Bool, isSheltered: Bool, userRating: Int? = nil, note: String? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.graphNodeID = graphNodeID
            self.hasPower = hasPower
            self.isSheltered = isSheltered
            self.userRating = userRating
            self.note = note
        }
    }

    @Model
    nonisolated final class UserSettings {
        #Unique<UserSettings>([\.key])
        var key: String
        /// Monday of teaching week 1.
        var semesterStartDate: Date
        var seedVersion: Int

        init(key: String = "settings", semesterStartDate: Date, seedVersion: Int = 0) {
            self.key = key
            self.semesterStartDate = semesterStartDate
            self.seedVersion = seedVersion
        }
    }
}

@Model
nonisolated final class Course {
    #Unique<Course>([\.code])
    var code: String
    var title: String
    var colorSeed: Int
    @Relationship(deleteRule: .cascade, inverse: \ClassSession.course)
    var sessions: [ClassSession] = []

    init(code: String, title: String, colorSeed: Int = Int.random(in: 0..<12)) {
        self.code = code
        self.title = title
        self.colorSeed = colorSeed
    }
}

@Model
nonisolated final class ClassSession {
    var kind: SessionKind
    /// `Calendar` weekday convention: 1 = Sunday … 7 = Saturday.
    var dayOfWeek: Int
    /// Minutes from midnight — integer recurrence math, immune to timezone traps.
    var startMinutes: Int
    var durationMinutes: Int
    /// Bit i-1 set == session runs in teaching week i (1…13). Odd weeks = 0b1010101010101.
    var teachingWeeksMask: Int
    var venue: Venue?
    var course: Course?

    init(kind: SessionKind, dayOfWeek: Int, startMinutes: Int, durationMinutes: Int,
         teachingWeeksMask: Int = 0b1_1111_1111_1111, venue: Venue? = nil) {
        self.kind = kind
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.teachingWeeksMask = teachingWeeksMask
        self.venue = venue
    }

    func runsInTeachingWeek(_ week: Int) -> Bool {
        (1...13).contains(week) && teachingWeeksMask & (1 << (week - 1)) != 0
    }
}

@Model
nonisolated final class Venue {
    #Unique<Venue>([\.shortName])
    #Index<Venue>([\.shortName])
    var shortName: String
    var displayName: String
    var latitude: Double
    var longitude: Double
    /// Stable join into the immutable CampusGraph — deliberately a string key,
    /// not a relationship, so routing never faults managed objects.
    var graphNodeID: String
    var isIndoor: Bool

    init(shortName: String, displayName: String, latitude: Double, longitude: Double,
         graphNodeID: String, isIndoor: Bool) {
        self.shortName = shortName
        self.displayName = displayName
        self.latitude = latitude
        self.longitude = longitude
        self.graphNodeID = graphNodeID
        self.isIndoor = isIndoor
    }
}

