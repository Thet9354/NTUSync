import Foundation
import os

/// Sendable projection of a StudyBench (models can't cross the actor boundary).
nonisolated struct BenchCandidate: Sendable, Hashable {
    let graphNodeID: NodeID
    let hasPower: Bool
    let isSheltered: Bool
    let note: String?
}

nonisolated struct GapSuggestion: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let category: AmenityCategory?    // nil = study bench
    let walkMinutes: Int
    let destination: NodeID
}

/// The gap advisor: given a free window between classes, ranks nearby options
/// by *actual walk time* from the previous class's venue (via the route
/// engine), meal-aware and open-hours-aware. Fully offline.
nonisolated enum GapPlanner {
    static let minimumGapMinutes = 30
    static let maxWalkMinutes = 12.0

    static func suggestions(
        from origin: NodeID,
        gapStart: Date,
        gapMinutes: Int,
        benches: [BenchCandidate],
        amenities: AmenityDirectory,
        graph: CampusGraph,
        engine: RouteEngine,
        limit: Int = 4
    ) async -> [GapSuggestion] {
        guard gapMinutes >= minimumGapMinutes,
              let originNode = graph.nodes[origin] else { return [] }

        let minuteOfDay = minuteOfDay(gapStart)
        let mealWindow = (660...840).contains(minuteOfDay) || (1020...1230).contains(minuteOfDay)

        // Candidate pool: open amenities + benches, prefiltered by crow-flies
        // so we only run the router on plausible options.
        struct Candidate {
            let node: NodeID
            let title: String
            let detail: String
            let icon: String
            let category: AmenityCategory?
            let boosted: Bool
        }
        var pool: [Candidate] = []

        for amenity in amenities.amenities where amenity.isOpen(atMinuteOfDay: minuteOfDay) {
            let isFoodish = [.food, .supper, .cafe].contains(amenity.category)
            pool.append(Candidate(
                node: amenity.graphNodeID,
                title: amenity.name,
                detail: amenity.hoursText,
                icon: amenity.category.icon,
                category: amenity.category,
                boosted: mealWindow && isFoodish
            ))
        }
        for bench in benches {
            let traits = [bench.hasPower ? "power" : nil, bench.isSheltered ? "sheltered" : nil]
                .compactMap(\.self).joined(separator: " · ")
            pool.append(Candidate(
                node: bench.graphNodeID,
                title: bench.note ?? "Study bench",
                detail: traits.isEmpty ? "Study spot" : traits.capitalized,
                icon: bench.hasPower ? "powerplug.fill" : "chair.lounge.fill",
                category: nil,
                // Long gaps favour settling down with a socket over eating twice.
                boosted: !mealWindow && gapMinutes >= 45 && bench.hasPower
            ))
        }

        let prefiltered = pool
            .compactMap { candidate -> (Candidate, Double)? in
                guard let node = graph.nodes[candidate.node] else { return nil }
                return (candidate, originNode.coordinate.distance(to: node.coordinate))
            }
            .filter { $0.1 < maxWalkMinutes * 60 * 1.4 }   // generous crow-flies cut
            .sorted { $0.1 < $1.1 }
            .prefix(12)

        var scored: [(GapSuggestion, Double)] = []
        for (candidate, _) in prefiltered where candidate.node != origin {
            guard let route = try? await engine.route(RouteQuery(
                origin: origin, destination: candidate.node,
                departure: gapStart, profile: .fastest
            )) else { continue }
            let walkMinutes = route.totalSeconds / 60
            guard walkMinutes <= maxWalkMinutes else { continue }
            let score = route.totalSeconds - (candidate.boosted ? 240 : 0)
            scored.append((GapSuggestion(
                id: "\(candidate.title)-\(candidate.node.rawValue)",
                title: candidate.title,
                detail: "\(max(1, Int(walkMinutes))) min walk · \(candidate.detail)",
                icon: candidate.icon,
                category: candidate.category,
                walkMinutes: max(1, Int(walkMinutes)),
                destination: candidate.node
            ), score))
        }

        var seen = Set<String>()
        return scored
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map(\.self)
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
