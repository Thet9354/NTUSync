import Foundation
import SwiftData
import os

/// All background writes go through this model actor; SwiftUI reads use
/// `@Query` on the main context.
@ModelActor
actor PersistenceStore {

    // MARK: Seeding (transactional + idempotent)

    private struct VenueSeed: Codable {
        let shortName: String, displayName: String
        let latitude: Double, longitude: Double
        let graphNodeID: String, isIndoor: Bool
    }
    private struct BenchSeed: Codable {
        let latitude: Double, longitude: Double
        let graphNodeID: String
        let hasPower: Bool, isSheltered: Bool
        let note: String?
    }
    private struct VenueDocument: Codable { let seedVersion: Int; let venues: [VenueSeed] }
    private struct BenchDocument: Codable { let seedVersion: Int; let benches: [BenchSeed] }

    func seedIfNeeded(bundle: Bundle = .main) throws {
        let settings = try fetchOrCreateSettings()

        guard let venuesURL = bundle.url(forResource: "SeedVenues", withExtension: "json"),
              let benchesURL = bundle.url(forResource: "SeedBenches", withExtension: "json") else {
            Logger.persistence.fault("seed resources missing from bundle")
            return
        }
        let venueDoc = try JSONDecoder().decode(VenueDocument.self, from: Data(contentsOf: venuesURL))
        let benchDoc = try JSONDecoder().decode(BenchDocument.self, from: Data(contentsOf: benchesURL))
        let bundledVersion = max(venueDoc.seedVersion, benchDoc.seedVersion)

        guard settings.seedVersion < bundledVersion else {
            Logger.persistence.debug("seed up to date (version \(settings.seedVersion))")
            return
        }
        Logger.persistence.info("seeding: \(settings.seedVersion) -> \(bundledVersion)")

        let existingVenueNames = Set(try modelContext.fetch(FetchDescriptor<Venue>()).map(\.shortName))
        var insertedVenues = 0
        for seed in venueDoc.venues where !existingVenueNames.contains(seed.shortName) {
            modelContext.insert(Venue(
                shortName: seed.shortName, displayName: seed.displayName,
                latitude: seed.latitude, longitude: seed.longitude,
                graphNodeID: seed.graphNodeID, isIndoor: seed.isIndoor
            ))
            insertedVenues += 1
        }

        var insertedBenches = 0
        if try modelContext.fetchCount(FetchDescriptor<StudyBench>()) == 0 {
            for seed in benchDoc.benches {
                modelContext.insert(StudyBench(
                    latitude: seed.latitude, longitude: seed.longitude,
                    graphNodeID: seed.graphNodeID,
                    hasPower: seed.hasPower, isSheltered: seed.isSheltered,
                    note: seed.note
                ))
                insertedBenches += 1
            }
        }

        settings.seedVersion = bundledVersion
        try modelContext.save()
        Logger.persistence.info("seed complete: +\(insertedVenues) venues, +\(insertedBenches) benches")
    }

    func fetchOrCreateSettings() throws -> UserSettings {
        if let existing = try modelContext.fetch(FetchDescriptor<UserSettings>()).first {
            return existing
        }
        // Default anchor: AY26/27 semester 1 teaching week 1 (Mon 10 Aug 2026).
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 10
        let start = Calendar.current.date(from: components) ?? .now
        let settings = UserSettings(semesterStartDate: start)
        modelContext.insert(settings)
        try modelContext.save()
        Logger.persistence.info("created default settings, semester start \(start)")
        return settings
    }
}
