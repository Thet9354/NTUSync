import Foundation

nonisolated struct RouteQuery: Hashable, Sendable {
    var origin: NodeID
    var destination: NodeID
    var departure: Date
    var profile: TravelProfile
}

nonisolated struct RouteLeg: Hashable, Sendable, Identifiable {
    let kind: EdgeKind
    let line: ShuttleLineID?
    let nodes: [NodeID]            // node sequence including both endpoints
    let metres: Double
    let seconds: Double
    /// Estimated shuttle boarding instant; nil for foot legs.
    let boardingTime: Date?

    var id: String { "\(kind.rawValue)-\(nodes.first?.rawValue ?? "")-\(nodes.last?.rawValue ?? "")" }
}

nonisolated struct Route: Hashable, Sendable {
    let legs: [RouteLeg]
    let departureTime: Date
    let arrivalTime: Date
    let totalWalkMetres: Double
    let exposedMetres: Double      // rain-weighted exposed distance

    var totalSeconds: Double { arrivalTime.timeIntervalSince(departureTime) }
    var origin: NodeID? { legs.first?.nodes.first }
    var destination: NodeID? { legs.last?.nodes.last }
}

nonisolated enum RoutingError: Error, Equatable {
    case unknownNode(NodeID)
    case noRouteFound
}
