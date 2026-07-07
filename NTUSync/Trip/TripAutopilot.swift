import Foundation

/// Pure decision logic for sensor-driven phase transitions. Given a GPS fix
/// and the active route, decides whether the trip should advance — kept free
/// of CoreLocation so every rule is unit-testable.
nonisolated struct TripAutopilot: Sendable {
    /// Arrival radii in metres. Boarding detection is tighter than riding
    /// detection because stops sit close to the roadside path network.
    static let stopArrivalRadius = 30.0
    static let rideDetectionRadius = 45.0
    static let destinationArrivalRadius = 30.0
    /// A fix worse than this cannot be trusted for a transition decision.
    static let maxUsableAccuracy = 50.0

    let route: Route

    /// The stop where the first shuttle leg is boarded, if any.
    var boardingStop: NodeID? {
        route.legs.first { $0.kind == .shuttle }?.nodes.first
    }

    /// The stop where the last shuttle leg is left, if any.
    var alightingStop: NodeID? {
        route.legs.last { $0.kind == .shuttle }?.nodes.last
    }

    /// Intermediate + terminal stops of all shuttle legs (everything after boarding).
    var downstreamShuttleStops: [NodeID] {
        route.legs.filter { $0.kind == .shuttle }.flatMap { $0.nodes.dropFirst() }
    }

    /// Returns the phase to advance to, or nil to stay put.
    /// `locate` resolves a node to its coordinate (backed by the campus graph).
    func suggestedTransition(
        from phase: TripPhase,
        fix: GeoPoint,
        accuracy: Double,
        locate: (NodeID) -> GeoPoint?
    ) -> TripPhase? {
        guard accuracy >= 0, accuracy <= Self.maxUsableAccuracy else { return nil }

        func distance(to node: NodeID?) -> Double? {
            node.flatMap(locate).map(fix.distance(to:))
        }

        switch phase {
        case .walkingToStop:
            if let d = distance(to: boardingStop), d <= Self.stopArrivalRadius {
                return .waitingForBus
            }
        case .waitingForBus:
            // Riding is detected by proximity to any downstream stop: the bus
            // carried us somewhere the walk there wouldn't plausibly reach yet.
            for stop in downstreamShuttleStops {
                if let coordinate = locate(stop),
                   fix.distance(to: coordinate) <= Self.rideDetectionRadius {
                    return .riding
                }
            }
        case .riding:
            if let d = distance(to: alightingStop), d <= Self.stopArrivalRadius {
                return .walkingToClass
            }
        case .walkingToClass:
            if let d = distance(to: route.destination), d <= Self.destinationArrivalRadius {
                return .arrived
            }
        case .arrived:
            break
        }
        return nil
    }

    /// Projects a fix onto the route as a 1-D arc-length coordinate — the
    /// reconciliation input for `RouteProgressEstimator` after GPS reacquisition.
    /// Returns nil when the fix is further than `corridor` from every node.
    func projectOntoRoute(fix: GeoPoint, corridor: Double = 80, locate: (NodeID) -> GeoPoint?) -> Double? {
        var travelled = 0.0
        var best: (distance: Double, along: Double)?
        for leg in route.legs {
            let metresPerNode = leg.nodes.count > 1 ? leg.metres / Double(leg.nodes.count - 1) : 0
            for (index, node) in leg.nodes.enumerated() {
                guard let coordinate = locate(node) else { continue }
                let d = fix.distance(to: coordinate)
                let along = travelled + Double(index) * metresPerNode
                if best == nil || d < best!.distance {
                    best = (d, along)
                }
            }
            travelled += leg.metres
        }
        guard let best, best.distance <= corridor else { return nil }
        return min(best.along, route.legs.reduce(0) { $0 + $1.metres })
    }
}
