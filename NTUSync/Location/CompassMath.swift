import Foundation

/// Where the compass arrow should point: the next meaningful checkpoint
/// (leg-boundary node) on the active route.
nonisolated struct CompassTarget: Sendable, Equatable {
    let nodeID: NodeID
    let coordinate: GeoPoint
    let distanceMetres: Double
    /// Absolute bearing from the user's position, 0° = true north, clockwise.
    let bearingDegrees: Double
}

/// Pure math for compass mode — the honest 80% of AR navigation
/// (`ARGeoTrackingConfiguration` has no Singapore coverage): a big arrow that
/// rotates toward the next checkpoint using device heading. Everything here is
/// integer/trig arithmetic on value types; the CLHeading plumbing stays thin.
nonisolated enum CompassMath {

    /// Within this range of a checkpoint the arrow advances to the next one.
    static let arrivalRadiusMetres = 25.0
    /// CLHeading accuracy (degrees) beyond which we warn rather than trust —
    /// heading is never trusted indoors (same doctrine as dead reckoning).
    static let reliableAccuracyDegrees = 30.0

    /// Initial great-circle bearing in degrees [0, 360), 0 = true north.
    static func bearing(from: GeoPoint, to: GeoPoint) -> Double {
        let phi1 = from.latitude * .pi / 180
        let phi2 = to.latitude * .pi / 180
        let dLambda = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        let theta = atan2(y, x) * 180 / .pi
        return (theta + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Arrow rotation relative to device-up, normalised to (-180, 180]:
    /// 0 = straight ahead, positive = clockwise (turn right).
    static func relativeAngle(bearing: Double, heading: Double) -> Double {
        var delta = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Eighth-wind glyph for a relative angle — the "140 m ↗" part.
    static func arrowGlyph(relativeAngle: Double) -> String {
        let glyphs = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
        let normalised = (relativeAngle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return glyphs[Int(((normalised + 22.5) / 45).truncatingRemainder(dividingBy: 8)) % 8]
    }

    /// Campus-scale distance text: metres below ~1 km, otherwise one-decimal km.
    static func distanceText(metres: Double) -> String {
        metres >= 950 ? String(format: "%.1f km", metres / 1000)
                      : "\(Int(metres.rounded())) m"
    }

    static func isHeadingReliable(accuracyDegrees: Double) -> Bool {
        accuracyDegrees >= 0 && accuracyDegrees <= reliableAccuracyDegrees
    }

    /// The next leg-boundary checkpoint ahead of the user. The route's node
    /// chain is the map-matching prior: snap to the nearest chain node, target
    /// the first checkpoint at or past it, and advance once within the arrival
    /// radius. `coordinate` resolves node positions (graph lookup in the app,
    /// a dictionary in tests).
    static func nextCheckpoint(legs: [RouteLeg], position: GeoPoint,
                               coordinate: (NodeID) -> GeoPoint?) -> CompassTarget? {
        // Flatten legs into a consecutive-deduped chain; record leg-end indices.
        var chain: [(id: NodeID, point: GeoPoint)] = []
        var checkpointIndices: [Int] = []
        for leg in legs {
            for node in leg.nodes {
                if chain.last?.id != node, let point = coordinate(node) {
                    chain.append((node, point))
                }
            }
            if let lastNode = leg.nodes.last, chain.last?.id == lastNode {
                checkpointIndices.append(chain.count - 1)
            }
        }
        guard !chain.isEmpty, !checkpointIndices.isEmpty else { return nil }

        let nearestIndex = chain.indices.min {
            position.distance(to: chain[$0].point) < position.distance(to: chain[$1].point)
        } ?? 0
        var targetIndex = checkpointIndices.first { $0 >= nearestIndex } ?? checkpointIndices[checkpointIndices.count - 1]
        if position.distance(to: chain[targetIndex].point) < arrivalRadiusMetres,
           let next = checkpointIndices.first(where: { $0 > targetIndex }) {
            targetIndex = next
        }

        let target = chain[targetIndex]
        return CompassTarget(
            nodeID: target.id,
            coordinate: target.point,
            distanceMetres: position.distance(to: target.point),
            bearingDegrees: bearing(from: position, to: target.point)
        )
    }
}
