import Foundation
import ActivityKit

/// Trip lifecycle phases. Walk-only trips skip the bus phases.
nonisolated enum TripPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case walkingToStop, waitingForBus, riding, walkingToClass, arrived
}

nonisolated struct ClassGlance: Codable, Hashable, Sendable {
    var courseCode: String
    var venueShortName: String
    var startTime: Date
}

/// Shared between the app and the widget extension — must stay byte-identical
/// in both targets or ActivityKit decoding fails silently.
nonisolated struct TripActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var phase: TripPhase
        var busLineName: String?
        /// Drives Text(timerInterval:) countdowns — the countdown itself never
        /// requires a push (see LiveActivityCoordinator cadence rules).
        var boardingWindow: ClosedRange<Date>?
        var arrivalEstimate: Date
        var nextClass: ClassGlance?
        var stepsSoFar: Int
    }

    /// Immutable per activity.
    var routeSummary: String
    var destinationNodeID: String
}
