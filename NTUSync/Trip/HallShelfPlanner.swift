import Foundation

nonisolated struct HallShelfItem: Identifiable, Sendable, Hashable {
    let id: String
    let slot: HallShelfPlanner.Slot
    let title: String
    let detail: String
    let icon: String
    let category: AmenityCategory?    // nil = study bench
    let walkMinutes: Int
    let destination: NodeID
}

/// The my-hall shelf: for each slot (food, groceries, gym, bench), the nearest
/// currently-open option ranked by *actual walk time from the user's hall*
/// (route engine, not crow-flies). Fully offline.
nonisolated enum HallShelfPlanner {

    enum Slot: String, CaseIterable, Sendable {
        case food, groceries, gym, bench

        var displayName: String {
            switch self {
            case .food: "Eat"
            case .groceries: "Groceries"
            case .gym: "Gym"
            case .bench: "Study"
            }
        }

        /// Which amenity categories feed this slot; nil = study benches.
        var categories: Set<AmenityCategory>? {
            switch self {
            case .food: [.food, .supper, .cafe]
            case .groceries: [.supermarket]
            case .gym: [.gym]
            case .bench: nil
            }
        }
    }

    static let maxWalkMinutes = 20.0
    /// Route only the closest few crow-flies candidates per slot.
    static let probesPerSlot = 3

    static func shelf(
        from home: NodeID,
        at date: Date,
        benches: [BenchCandidate],
        amenities: AmenityDirectory,
        graph: CampusGraph,
        engine: RouteEngine
    ) async -> [HallShelfItem] {
        guard let homeNode = graph.nodes[home] else { return [] }

        var items: [HallShelfItem] = []
        for slot in Slot.allCases {
            struct Candidate {
                let node: NodeID
                let title: String
                let detail: String
                let icon: String
                let category: AmenityCategory?
            }
            var pool: [Candidate] = []
            if let categories = slot.categories {
                for amenity in amenities.amenities(in: categories) where amenity.isOpen(at: date) {
                    pool.append(Candidate(
                        node: amenity.graphNodeID, title: amenity.name,
                        detail: amenity.hoursText, icon: amenity.category.icon,
                        category: amenity.category
                    ))
                }
            } else {
                for bench in benches {
                    let traits = [bench.hasPower ? "power" : nil,
                                  bench.isSheltered ? "sheltered" : nil]
                        .compactMap(\.self).joined(separator: " · ")
                    pool.append(Candidate(
                        node: bench.graphNodeID,
                        title: bench.note ?? "Study bench",
                        detail: traits.isEmpty ? "Study spot" : traits.capitalized,
                        icon: bench.hasPower ? "powerplug.fill" : "chair.lounge.fill",
                        category: nil
                    ))
                }
            }

            let probes = pool
                .compactMap { candidate -> (Candidate, Double)? in
                    guard candidate.node != home,
                          let node = graph.nodes[candidate.node] else { return nil }
                    return (candidate, homeNode.coordinate.distance(to: node.coordinate))
                }
                .sorted { $0.1 < $1.1 }
                .prefix(probesPerSlot)

            var best: (HallShelfItem, Double)?
            for (candidate, _) in probes {
                guard let route = try? await engine.route(RouteQuery(
                    origin: home, destination: candidate.node,
                    departure: date, profile: .fastest
                )) else { continue }
                let minutes = route.totalSeconds / 60
                guard minutes <= maxWalkMinutes else { continue }
                if best == nil || route.totalSeconds < best!.1 {
                    best = (HallShelfItem(
                        id: "\(slot.rawValue).\(candidate.node.rawValue)",
                        slot: slot,
                        title: candidate.title,
                        detail: "\(max(1, Int(minutes))) min · \(candidate.detail)",
                        icon: candidate.icon,
                        category: candidate.category,
                        walkMinutes: max(1, Int(minutes)),
                        destination: candidate.node
                    ), route.totalSeconds)
                }
            }
            if let best {
                items.append(best.0)
            }
        }
        return items
    }
}
