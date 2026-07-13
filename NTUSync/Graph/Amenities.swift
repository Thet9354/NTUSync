import Foundation
import os

nonisolated enum AmenityCategory: String, Codable, CaseIterable, Sendable {
    case food, supper, cafe, supermarket, alcohol, gym, recreation, printing, atm, clinic

    var displayName: String {
        switch self {
        case .food: "Food"
        case .supper: "Supper"
        case .cafe: "Cafés"
        case .supermarket: "Groceries"
        case .alcohol: "Drinks"
        case .gym: "Gym"
        case .recreation: "Recreation"
        case .printing: "Printing"
        case .atm: "ATM"
        case .clinic: "Clinic"
        }
    }

    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .supper: "moon.stars.fill"
        case .cafe: "cup.and.saucer.fill"
        case .supermarket: "cart.fill"
        case .alcohol: "wineglass.fill"
        case .gym: "dumbbell.fill"
        case .recreation: "figure.outdoor.cycle"
        case .printing: "printer.fill"
        case .atm: "banknote.fill"
        case .clinic: "cross.case.fill"
        }
    }
}

/// A campus point of interest. Immutable curated data bundled with the app,
/// joined to the routing graph by node ID — the same pattern as the graph
/// itself, so no database migration is needed to grow this dataset.
nonisolated struct Amenity: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let category: AmenityCategory
    let graphNodeID: NodeID
    let latitude: Double
    let longitude: Double
    /// Daily opening window in minutes from midnight; wraps past midnight when
    /// close < open (supper spots). Both nil = always open.
    let openMinute: Int?
    let closeMinute: Int?
    let note: String?

    var coordinate: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    func isOpen(atMinuteOfDay minute: Int) -> Bool {
        guard let openMinute, let closeMinute else { return true }
        if openMinute <= closeMinute {
            return minute >= openMinute && minute < closeMinute
        }
        // Wraps midnight, e.g. 18:00–02:00.
        return minute >= openMinute || minute < closeMinute
    }

    func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return isOpen(atMinuteOfDay: (comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    var hoursText: String {
        guard let openMinute, let closeMinute else { return "Open 24h" }
        func fmt(_ m: Int) -> String { String(format: "%02d:%02d", m / 60 % 24, m % 60) }
        return "\(fmt(openMinute))–\(fmt(closeMinute))"
    }
}

nonisolated struct AmenityDirectory: Sendable {
    let amenities: [Amenity]

    func amenities(in categories: Set<AmenityCategory>) -> [Amenity] {
        categories.isEmpty ? amenities : amenities.filter { categories.contains($0.category) }
    }

    private struct Document: Codable {
        let formatVersion: Int
        let amenities: [Amenity]
    }

    static func loadBundled(_ bundle: Bundle = .main) throws -> AmenityDirectory {
        guard let url = bundle.url(forResource: "Amenities", withExtension: "json") else {
            Logger.routing.fault("Amenities.json missing from bundle")
            throw GraphLoadingError.resourceMissing("Amenities.json")
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        Logger.routing.info("Loaded \(document.amenities.count) amenities")
        return AmenityDirectory(amenities: document.amenities)
    }
}
