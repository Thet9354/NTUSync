import Foundation

nonisolated struct NodeID: Hashable, Sendable, RawRepresentable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

nonisolated struct ShuttleLineID: Hashable, Sendable, RawRepresentable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

nonisolated struct GeoPoint: Hashable, Sendable, Codable {
    var latitude: Double
    var longitude: Double

    /// Great-circle distance in metres (haversine).
    func distance(to other: GeoPoint) -> Double {
        let radius = 6_371_000.0
        let phi1 = latitude * .pi / 180
        let phi2 = other.latitude * .pi / 180
        let dPhi = (other.latitude - latitude) * .pi / 180
        let dLambda = (other.longitude - longitude) * .pi / 180
        let h = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}

nonisolated enum EdgeKind: String, Codable, Sendable, CaseIterable {
    case walk
    case shelteredWalk
    case stairs
    case shuttle
    case indoor

    var isFootTravel: Bool { self != .shuttle }

    /// Fraction of the edge exposed to rain, used by the rain-averse cost profile.
    var rainExposure: Double {
        switch self {
        case .walk: 1.0
        case .stairs: 0.3
        case .shelteredWalk, .indoor, .shuttle: 0.0
        }
    }
}

nonisolated struct GraphNode: Sendable, Hashable {
    let id: NodeID
    let coordinate: GeoPoint
    let elevation: Double
    let isIndoor: Bool
    let displayName: String?
}

nonisolated struct GraphEdge: Sendable, Hashable {
    let from: NodeID
    let to: NodeID
    let kind: EdgeKind
    let lengthMetres: Double
    let elevationDelta: Double
    let line: ShuttleLineID?
}
