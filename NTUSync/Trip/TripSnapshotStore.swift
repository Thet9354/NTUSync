import Foundation
import os

/// Lightweight crash/relaunch recovery (design spec §5.4): enough state to
/// rebind to a surviving Live Activity and resume pushing.
nonisolated struct ActiveTripSnapshot: Codable, Equatable, Sendable {
    var activityID: String?
    var route: Route
    var summary: String
    var phase: TripPhase
    var stepsSoFar: Int
    var nextClass: ClassGlance?
}

nonisolated struct TripSnapshotStore: Sendable {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        fileURL = base.appendingPathComponent("ActiveTripSnapshot.json")
    }

    func load() -> ActiveTripSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(ActiveTripSnapshot.self, from: data)
        } catch {
            Logger.liveActivity.error("snapshot unreadable, discarding: \(String(describing: error))")
            clear()
            return nil
        }
    }

    func save(_ snapshot: ActiveTripSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            Logger.liveActivity.error("snapshot save failed: \(String(describing: error))")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
