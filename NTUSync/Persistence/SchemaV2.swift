import Foundation
import SwiftData

/// Version 2: bench photos, per-node checkpoint photos, and the my-hall /
/// leave-alert settings. All additions are optional or defaulted, so V1 → V2
/// is a lightweight migration.
nonisolated enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Course.self, ClassSession.self, Venue.self,
         StudyBench.self, UserSettings.self, CheckpointPhoto.self]
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
        /// JPEG data; external storage keeps blobs out of the main store file.
        @Attribute(.externalStorage) var photo: Data?

        init(latitude: Double, longitude: Double, graphNodeID: String,
             hasPower: Bool, isSheltered: Bool, userRating: Int? = nil,
             note: String? = nil, photo: Data? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.graphNodeID = graphNodeID
            self.hasPower = hasPower
            self.isSheltered = isSheltered
            self.userRating = userRating
            self.note = note
            self.photo = photo
        }
    }

    @Model
    nonisolated final class UserSettings {
        #Unique<UserSettings>([\.key])
        var key: String
        /// Monday of teaching week 1.
        var semesterStartDate: Date
        var seedVersion: Int
        /// Graph node of the user's hall — powers the my-hall shelf, "route
        /// home", and the origin for leave-now alerts. Same string-key join as
        /// venues (never a relationship).
        var homeNodeID: String?
        var leaveAlertsEnabled: Bool = false
        /// Minutes of slack added on top of the computed route time.
        var leaveBufferMinutes: Int = 10

        init(key: String = "settings", semesterStartDate: Date, seedVersion: Int = 0,
             homeNodeID: String? = nil, leaveAlertsEnabled: Bool = false,
             leaveBufferMinutes: Int = 10) {
            self.key = key
            self.semesterStartDate = semesterStartDate
            self.seedVersion = seedVersion
            self.homeNodeID = homeNodeID
            self.leaveAlertsEnabled = leaveAlertsEnabled
            self.leaveBufferMinutes = leaveBufferMinutes
        }
    }

    /// User-shot imagery for a graph node — the offline/indoor fallback where
    /// Apple Look Around has no coverage. Keyed by node ID, one photo per node.
    @Model
    nonisolated final class CheckpointPhoto {
        #Unique<CheckpointPhoto>([\.nodeID])
        #Index<CheckpointPhoto>([\.nodeID])
        var nodeID: String
        @Attribute(.externalStorage) var photo: Data

        init(nodeID: String, photo: Data) {
            self.nodeID = nodeID
            self.photo = photo
        }
    }
}

/// These models are unchanged in V3, so their typealiases still point here.
/// The migration plan lives in the current version's file (SchemaV3.swift).
typealias StudyBench = SchemaV2.StudyBench
typealias UserSettings = SchemaV2.UserSettings
typealias CheckpointPhoto = SchemaV2.CheckpointPhoto
