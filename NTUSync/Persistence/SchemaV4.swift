import Foundation
import SwiftData

/// Version 4: user-pinned places on the Explore map. `UserPlace` is brand new;
/// every other model is unchanged and referenced from its home version, so
/// V3 → V4 is a lightweight stage.
nonisolated enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Course.self, ClassSession.self, Venue.self,
         SchemaV2.StudyBench.self, SchemaV2.UserSettings.self, SchemaV2.CheckpointPhoto.self,
         SchemaV3.ExamEvent.self,
         UserPlace.self]
    }

    /// A user-added pin: their own food spot, supper haunt, café — or a fully
    /// custom marker with no category at all. Mirrors the curated `Amenity`
    /// shape (same string-key join to the graph) but lives in the store so it
    /// syncs with the user's edits and deletions.
    @Model
    nonisolated final class UserPlace {
        var name: String
        /// `AmenityCategory.rawValue`; nil = custom pin.
        var categoryRaw: String?
        var latitude: Double
        var longitude: Double
        /// Nearest graph node at creation time — powers "Take me there".
        var graphNodeID: String
        var note: String?

        init(name: String, categoryRaw: String?, latitude: Double, longitude: Double,
             graphNodeID: String, note: String? = nil) {
            self.name = name
            self.categoryRaw = categoryRaw
            self.latitude = latitude
            self.longitude = longitude
            self.graphNodeID = graphNodeID
            self.note = note
        }
    }
}

/// The rest of the app always talks to the *current* schema version.
typealias UserPlace = SchemaV4.UserPlace

extension UserPlace {
    var category: AmenityCategory? { categoryRaw.flatMap(AmenityCategory.init) }
    var icon: String { category?.icon ?? "mappin" }
}

nonisolated enum NTUSyncMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
         .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
         .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)]
    }
}
