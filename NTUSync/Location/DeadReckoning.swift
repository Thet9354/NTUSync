import Foundation

/// Detects GPS-denied conditions: horizontal accuracy worse than the threshold
/// sustained for the dwell duration.
nonisolated struct GpsDenialDetector: Sendable {
    var accuracyThreshold: Double = 50
    var dwellSeconds: TimeInterval = 10
    private var badSince: Date?

    mutating func ingest(accuracy: Double, at date: Date) -> Bool {
        if accuracy <= accuracyThreshold && accuracy >= 0 {
            badSince = nil
            return false
        }
        if let since = badSince {
            return date.timeIntervalSince(since) >= dwellSeconds
        }
        badSince = date
        return false
    }
}

/// Graph-constrained pedestrian dead reckoning: position is a 1-D arc-length
/// coordinate along the active route's edge chain. The route topology is the
/// map-matching prior — heading is never trusted indoors.
nonisolated struct RouteProgressEstimator: Sendable, Equatable {
    /// Estimated error grows by this fraction of distance walked while dead-reckoning.
    static let driftRate = 0.08
    /// A re-acquired fix disagreeing by more than this suggests the user left the route.
    static let replanThresholdMetres = 75.0

    let routeLengthMetres: Double
    private(set) var distanceAlongMetres: Double
    private(set) var confidenceRadiusMetres: Double
    private(set) var isDeadReckoning: Bool

    init(routeLengthMetres: Double, initialConfidence: Double = 15) {
        self.routeLengthMetres = routeLengthMetres
        self.distanceAlongMetres = 0
        self.confidenceRadiusMetres = initialConfidence
        self.isDeadReckoning = false
    }

    var fractionComplete: Double {
        routeLengthMetres > 0 ? min(1, distanceAlongMetres / routeLengthMetres) : 1
    }

    mutating func beginDeadReckoning() {
        isDeadReckoning = true
    }

    /// Advance by a pedometer distance delta, clamped to the route.
    mutating func advance(byMetres metres: Double) {
        guard metres > 0 else { return }
        distanceAlongMetres = min(routeLengthMetres, distanceAlongMetres + metres)
        if isDeadReckoning {
            confidenceRadiusMetres += Self.driftRate * metres
        }
    }

    enum Reconciliation: Equatable, Sendable {
        case snapped(driftMetres: Double)
        case replanSuggested(driftMetres: Double)
    }

    /// Reconcile with a re-acquired GPS fix already projected onto the route.
    mutating func reconcile(fixDistanceAlong: Double, accuracy: Double) -> Reconciliation {
        let drift = abs(fixDistanceAlong - distanceAlongMetres)
        isDeadReckoning = false
        confidenceRadiusMetres = max(accuracy, 5)
        if drift > Self.replanThresholdMetres {
            return .replanSuggested(driftMetres: drift)
        }
        distanceAlongMetres = min(routeLengthMetres, max(0, fixDistanceAlong))
        return .snapped(driftMetres: drift)
    }
}
